#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    THE influence-radius table for the map overlay. Every number that decides
    how far a zone projects its influence lives here and nowhere else, so the
    balance can be re-tuned by editing this one block.

    ============================================================================
    ==  PER-TYPE MULTIPLIERS  (x the "Influence range" setting)               ==
    ============================================================================
    ==                                                                        ==
    ==    Roadblock                0.75      600 m at the 800 m default       ==
    ==    Watchpost / camp         1.00      800 m                            ==
    ==    Resource / factory       1.00      800 m                            ==
    ==    Seaport                  1.00      800 m                            ==
    ==    Outpost                  1.25     1000 m                            ==
    ==    City / town              0.75-1.50 by marker size, see below        ==
    ==    Airfield                 1.75     1400 m                            ==
    ==    Rebel HQ                 not a multiplier - see below               ==
    ==    Anything not listed      1.00      800 m                            ==
    ==                                                                        ==
    ============================================================================

    The multiplier depends only on the zone TYPE, never on who owns it, so a
    rebel outpost and an occupier outpost push exactly as hard as each other.
    That symmetry is the point of the table: the previous model gave friendly
    zones the full link distance and enemy zones only their marker footprint,
    so a 30 m roadblock claimed a 2 km bubble while a real enemy base pushed
    back 200 m.

    Cities scale with their marker size, because fn_initZones sizes a town
    marker by how far its building density reaches: the search starts at 150 m
    and stops at 500 m. That range is mapped linearly onto 0.75x .. 1.50x and
    clamped, so a hamlet projects like a roadblock, a mid-sized town like an
    outpost and the largest city on the map sits between an outpost and an
    airfield. Using the marker rather than a population number keeps it
    map-agnostic: any world's towns are sized by the same code.

    The rebel HQ uses A3A_fnc_hqBuildRadius directly rather than a multiplier,
    so its reach is exactly the area it can build and garrison, and grows with
    the war tier (75 m -> 210 m). NOTE: that is far smaller than any other
    zone's reach and smaller than one grid cell on a large map, so
    fn_computeInfluenceZones floors every radius at 1.5 grid cells to stop the
    HQ disappearing entirely on an early-campaign map. See the report.

    Training scaling: every radius is multiplied by the caller's scale factor,
    which fn_computeInfluenceZones derives from skillFIA (rebel AI training,
    raised in HQ Management): 0.8x at skillFIA 1 rising to 1.2x at skillFIA 20.
    It is applied to every side, not only the rebels, so the per-type symmetry
    above is preserved - better-trained rebels widen the whole picture rather
    than getting a private bonus. (Captain decision: making it rebel-only is a
    one-line change here.)

Arguments:
    0: <NUMBER> Reference range in metres (the "Influence range" setting).
    1: <NUMBER> Overall scale factor, e.g. the training factor. (optional, default 1)

Return Value:
    <HASHMAP> marker name -> influence radius in metres. Markers that are not
              in any known type list are absent; callers must supply the
              default themselves (reference range x scale).

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    airportsX, citiesX, outposts, seaports, resourcesX, factories,
    outpostsFIA, controlsX  (public globals)
    A3A_fnc_hqBuildRadius
*/

params [["_refRange", 800, [0]], ["_scale", 1, [0]]];

private _radii = createHashMap;

// One helper, so the table below reads as a table.
private _fnc_set = {
    params ["_markers", "_mult"];
    private _r = _refRange * _mult * _scale;
    { _radii set [_x, _r] } forEach _markers;
};

// ---- The table ----------------------------------------------------------
// Later entries win, so anything listed twice takes its last multiplier.
[missionNamespace getVariable ["seaports", []],   1.00] call _fnc_set;
[missionNamespace getVariable ["resourcesX", []], 1.00] call _fnc_set;
[missionNamespace getVariable ["factories", []],  1.00] call _fnc_set;
[missionNamespace getVariable ["outposts", []],   1.25] call _fnc_set;
[missionNamespace getVariable ["airportsX", []],  1.75] call _fnc_set;

// Cities: by marker size, 150 m marker -> 0.75x, 500 m marker -> 1.50x.
private _citySizeMin = 150;
private _citySizeMax = 500;
private _cityMultMin = 0.75;
private _cityMultMax = 1.50;
private _citySlope = (_cityMultMax - _cityMultMin) / (_citySizeMax - _citySizeMin);
{
    private _size = markerSize _x;
    private _semi = (_size # 0) max (_size # 1);
    private _mult = _cityMultMin + (_semi - _citySizeMin) * _citySlope;
    _mult = (_mult max _cityMultMin) min _cityMultMax;
    _radii set [_x, _refRange * _mult * _scale];
} forEach (missionNamespace getVariable ["citiesX", []]);

// Rebel watchposts / roadblocks and enemy camps / roadblocks. Neither list
// records which it is, so use the same test fn_initMarkerTypes uses to decide:
// a minor site on a road is a roadblock, otherwise it is a camp / watchpost.
{
    private _pos = getMarkerPos _x;
    private _mult = [1.00, 0.75] select (isOnRoad _pos);
    _radii set [_x, _refRange * _mult * _scale];
} forEach ((missionNamespace getVariable ["outpostsFIA", []]) + (missionNamespace getVariable ["controlsX", []]));

// Rebel HQ: the area it can build and garrison, which grows with the war tier.
if (!isNil "tierWar") then {
    _radii set ["Synd_HQ", (call A3A_fnc_hqBuildRadius) * _scale];
};

_radii
