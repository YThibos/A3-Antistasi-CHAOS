#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the shared influence context: the single source of truth for WHICH
    zones project influence, HOW FAR each one reaches, and WHICH CONSTANTS the
    field model uses. Both consumers of the influence field are built on it:

      - A3A_fnc_computeInfluenceZones  (client) rasterises the field on a grid
        and contours it into the map overlay's borders.
      - A3A_fnc_computeSupplyGraph     (server) samples the field along
        corridors between zones to decide which supply edges survive.

    Before this function existed the collection loop lived inside
    fn_computeInfluenceZones, which meant the drawn border and anything else
    that wanted to know about influence could drift apart. They cannot now:
    both start here.

    ---- Why the settings must be global ------------------------------------
    A3A_CHAOS_influenceRange and A3A_CHAOS_influenceReach define the shape of
    the world, so they are registered with isGlobal = 1 in
    fn_initCHAOSSettings: the server's value is the one everybody gets. They
    used to be per-client, which was harmless while the overlay was pure
    decoration - two players simply saw two slightly different borders - but is
    not harmless now that the server derives supply connectivity from the same
    numbers. Presentation settings (fill, thickness, opacity, claim areas,
    enabled) stay per-client, because those are taste.

    ---- The one deliberate difference from the raster ----------------------
    The rasteriser floors every radius at 1.5 grid cells so that a zone smaller
    than the grid cannot vanish between sample points. That floor is a property
    of the GRID, not of the field, so it is applied there and not here. A point
    query has no grid and needs no floor. The practical effect is that a zone
    whose true radius is under ~1.5 cells draws slightly larger than it
    actually reaches; on Altis at the default settings no zone type is that
    small, so the two agree everywhere it matters.

Arguments:
    None

Return Value:
    <ARRAY> [_sideList, _sideZones, _consts, _buckets, _bucketCell]
        _sideList   <ARRAY of SIDE>  every side that holds ground, in the order
                                     found. Never contains sideUnknown.
        _sideZones  <ARRAY>          parallel to _sideList; each entry is an
                                     array of [_x, _y, _radius, _marker].
                                     Element order 0..2 is what the rasteriser
                                     already destructured, so it is unchanged.
        _consts     <ARRAY>          [_cap, _capTail, _tailW, _reach,
                                      _reachMult, _refRange, _trainScale]
        _buckets    <HASHMAP>        "i,j" -> [[_sideIdx, _x, _y, _r], ...],
                                     the spatial index A3A_fnc_influenceAt uses
                                     so a point query touches a handful of
                                     zones instead of all of them.
        _bucketCell <NUMBER>         bucket edge length in metres.
    Returns [] when the zone globals are not broadcast yet, or when no side
    holds any ground. Callers must handle the empty case.

Scope: Anywhere (server for the supply graph, client for the overlay)
Environment: Unscheduled
Public: No
Dependencies:
    markersX, outpostsFIA, controlsX, sidesX, teamPlayer, skillFIA (globals)
    A3A_CHAOS_influenceRange, A3A_CHAOS_influenceReach            (CBA, global)
    A3A_influenceCap, A3A_influenceCapTail, A3A_influenceTailWeight (overrides)
    A3A_fnc_zoneInfluenceRadii
*/

if (isNil "markersX" || {isNil "outpostsFIA"} || {isNil "sidesX"}) exitWith {
    Debug("influenceContext: zone globals not ready yet");
    []
};

// ---- Settings and model constants ---------------------------------------
// Written in the affirmative so a non-number, an out-of-range value and NaN
// all fall through to the default. A cap of zero or less would divide by zero
// in the saturation, so that one is not merely cosmetic.
private _refRange = missionNamespace getVariable ["A3A_CHAOS_influenceRange", 800];
if !(_refRange isEqualType 0) then { _refRange = 800 };
_refRange = ((round (_refRange / 100)) * 100) max 100 min 1400;

private _reach = missionNamespace getVariable ["A3A_CHAOS_influenceReach", 2.0];
if !(_reach isEqualType 0) then { _reach = 2.0 };
_reach = ((round (_reach / 0.5)) * 0.5) max 0 min 3;

private _cap = missionNamespace getVariable ["A3A_influenceCap", 1];
if !(_cap isEqualType 0 && {_cap >= 0.05} && {_cap <= 100}) then { _cap = 1 };

private _capTail = missionNamespace getVariable ["A3A_influenceCapTail", 0.05];
if !(_capTail isEqualType 0 && {_capTail >= 0} && {_capTail <= 1}) then { _capTail = 0.05 };

private _tailW = missionNamespace getVariable ["A3A_influenceTailWeight", 0.05];
if !(_tailW isEqualType 0 && {_tailW >= 0} && {_tailW <= 0.5}) then { _tailW = 0.05 };

// Reach 0, or a zero weight, switches the faint long cone off entirely.
if (_reach <= 0 || {_tailW <= 0}) then { _reach = 0; _tailW = 0 };
private _reachMult = 1 max _reach;

// Rebel AI training widens the Guerilla side's reach and nobody else's.
private _skill = missionNamespace getVariable ["skillFIA", 1];
if !(_skill isEqualType 0) then { _skill = 1 };
private _trainScale = 0.8 + 0.4 * (((_skill max 1) min 20) - 1) / 19;

private _radii = [_refRange] call A3A_fnc_zoneInfluenceRadii;

// ---- Collect the zones that hold ground, grouped by side ----------------
private _controls = missionNamespace getVariable ["controlsX", []];
private _allZones = markersX + outpostsFIA + _controls;

private _sideList  = [];
private _sideZones = [];

{
    private _mrk = _x;
    private _pos = getMarkerPos _mrk;
    // Markers never broadcast to this machine report [0,0,0].
    if (_pos isEqualTo [0,0,0]) then { continue };

    private _side = sidesX getVariable [_mrk, sideUnknown];
    if (_side isEqualTo sideUnknown) then { continue };

    private _radius = _radii getOrDefault [_mrk, _refRange];
    if (_side isEqualTo teamPlayer) then { _radius = _radius * _trainScale };
    if (_radius <= 0) then { continue };

    private _idx = _sideList find _side;
    if (_idx < 0) then {
        _sideList pushBack _side;
        _sideZones pushBack [];
        _idx = (count _sideList) - 1;
    };
    (_sideZones select _idx) pushBack [_pos # 0, _pos # 1, _radius, _mrk];
} forEach _allZones;

// ---- Enemy off-map entry points -----------------------------------------
// NATO_carrier and CSAT_carrier are the Occupant and Invader support corridors -
// where their reinforcements arrive from off the map. fn_initVarServer only ever
// sets their marker TEXT from the faction template; they are not in markersX, no
// side owns them in sidesX, and so they projected no influence at all and could
// not anchor anything.
//
// They are given an explicit side and a flat radius here. That radius is a
// setting rather than a type multiplier because these are not zones anyone can
// capture: the number is asking "how far inland does off-map support reach",
// which is a different question from how hard a base pushes.
private _carrierRadius = missionNamespace getVariable ["A3A_CHAOS_supplyCarrierRadius", 1500];
if !(_carrierRadius isEqualType 0 && {_carrierRadius > 0}) then { _carrierRadius = 1500 };

{
    _x params ["_cMrk", "_cSide"];
    private _cPos = getMarkerPos _cMrk;
    if (_cPos isEqualTo [0,0,0]) then { continue };

    private _idx = _sideList find _cSide;
    if (_idx < 0) then {
        _sideList pushBack _cSide;
        _sideZones pushBack [];
        _idx = (count _sideList) - 1;
    };
    (_sideZones select _idx) pushBack [_cPos # 0, _cPos # 1, _carrierRadius, _cMrk];
} forEach (
    // gameMode 3 runs without Invaders, and a side global can be nil before init
    // completes, so each entry is admitted only if its side actually exists.
    ([] + (if (isNil "Occupants") then { [] } else { [["NATO_carrier", Occupants]] })
       + (if (isNil "Invaders")  then { [] } else { [["CSAT_carrier", Invaders]] }))
);

if (_sideList isEqualTo []) exitWith {
    Debug("influenceContext: no owned zones");
    []
};

// ---- Spatial index for point queries ------------------------------------
// Every zone is scattered into each bucket its OUTER cone's bounding box
// touches, so a point query reads exactly one bucket and gets a superset of
// the zones that can reach it. A bucket wider than most cones keeps the
// scatter cheap: at the Altis defaults a zone lands in roughly two dozen
// buckets, and the whole index costs a few thousand pushBacks once per
// rebuild - against 45k+ cone evaluations saved on every corridor sample.
private _bucketCell = 2000;
private _buckets = createHashMap;

{
    private _sideIdx = _forEachIndex;
    {
        _x params ["_px", "_py", "_r0"];
        private _ro = _r0 * _reachMult;
        private _i0 = floor ((_px - _ro) / _bucketCell);
        private _i1 = floor ((_px + _ro) / _bucketCell);
        private _j0 = floor ((_py - _ro) / _bucketCell);
        private _j1 = floor ((_py + _ro) / _bucketCell);
        private _entry = [_sideIdx, _px, _py, _r0];
        for "_i" from _i0 to _i1 do {
            for "_j" from _j0 to _j1 do {
                private _key = format ["%1,%2", _i, _j];
                (_buckets getOrDefault [_key, [], true]) pushBack _entry;
            };
        };
    } forEach _x;
} forEach _sideZones;

private _consts = [_cap, _capTail, _tailW, _reach, _reachMult, _refRange, _trainScale];

private _dbgCounts = _sideZones apply { count _x };
Debug_2("influenceContext: %1 sides, zones per side %2", count _sideList, _dbgCounts);

[_sideList, _sideZones, _consts, _buckets, _bucketCell]
