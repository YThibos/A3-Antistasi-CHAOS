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
    ==    Rebel HQ                 1.25     1000 m (an outpost's reach)        ==
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

    The rebel HQ takes an outpost's 1.25x, exactly like any other zone type.
    It used to read A3A_fnc_hqBuildRadius instead, so that its influence was
    precisely the area it can build and garrison - but that is 75 m at war tier
    1 and 210 m at war tier 10, well under one grid cell on an Altis-sized map.
    Measured, it produced zero contour segments early game: the 1.5-cell radius
    floor in fn_computeInfluenceZones, not this table, was setting the HQ's
    reach. A3A_fnc_hqBuildRadius is untouched and still drives the HQ BUILD
    area and the "Synd_HQ" claim ring (fn_updateHQMarkerRadius), both of which
    still grow with the war tier. Only the influence field's radius changed.

    Training scaling is NOT applied here. This table is a pure per-type lookup
    and knows nothing about ownership; fn_computeInfluenceZones knows each
    zone's side and multiplies the Guerilla side's radii - and only those - by
    the training factor it derives from skillFIA. That is deliberate: skillFIA
    is the player faction's own training level, so scaling every side by it let
    the player's own investment inflate enemy reach as well.

Arguments:
    0: <NUMBER> Reference range in metres (the "Influence range" setting).

Return Value:
    <HASHMAP> marker name -> influence radius in metres. Markers that are not
              in any known type list are absent; callers must supply the
              default themselves (the reference range, i.e. a 1.00x multiplier).

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    airportsX, citiesX, outposts, seaports, resourcesX, factories,
    outpostsFIA, controlsX  (public globals)
*/

params [["_refRange", 800, [0]]];

private _radii = createHashMap;

// One helper, so the table below reads as a table.
private _fnc_set = {
    params ["_markers", "_mult"];
    private _r = _refRange * _mult;
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
    _radii set [_x, _refRange * _mult];
} forEach (missionNamespace getVariable ["citiesX", []]);

// Rebel watchposts / roadblocks and enemy camps / roadblocks. Neither list
// records which it is, so use the same test fn_initMarkerTypes uses to decide:
// a minor site on a road is a roadblock, otherwise it is a camp / watchpost.
{
    private _pos = getMarkerPos _x;
    private _mult = [1.00, 0.75] select (isOnRoad _pos);
    _radii set [_x, _refRange * _mult];
} forEach ((missionNamespace getVariable ["outpostsFIA", []]) + (missionNamespace getVariable ["controlsX", []]));

// Rebel HQ: pushes like an outpost. Its build/claim radius is a different
// number for a different job (see A3A_fnc_hqBuildRadius) and is not used here.
[["Synd_HQ"], 1.25] call _fnc_set;

_radii
