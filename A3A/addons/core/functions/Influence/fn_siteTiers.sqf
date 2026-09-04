#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Recomputes the CHAOS upgrade tier of every rebel-held resource and factory,
    and publishes the result.

    ---- Tier is DERIVED, never stored -------------------------------------
    A site's tier is read off the structures standing on it:

        Tier 0  nothing built                       - vanilla behaviour
        Tier 1  a supply warehouse on the site      - Land_Warehouse_03_F
        Tier 2  warehouse + power generator         - Land_PowerGenerator_F

    Deriving it rather than storing a number per marker is what keeps this out
    of the save system entirely. The structures are already persisted (they go
    into the marker's garrison via fn_buildingComplete, or into
    A3A_buildingsToSave), so the tier persists with them for free, and it also
    means the agreed destruction rule needs no code at all: blow up the
    warehouse and the site is Tier 0 again on the next recompute, eligible for
    the upgrade mission once more.

    There is deliberately NO marker variable on the structures. A saved and
    restored building does not carry custom variables back, so a variable-based
    test would silently drop every tier on campaign reload - the exact class of
    bug hard rule 8 exists to prevent. Class plus proximity survives anything
    that can restore the building at all.

    The side effect of testing by class is that a warehouse built at a resource
    site by any other route also counts. That is treated as correct rather than
    as a loophole: the fiction is "this site has a warehouse", not "this site
    has a warehouse issued by the quartermaster".

    ---- What tier does ----------------------------------------------------
      - Tier 0 sites are NOT nodes in the player's supply graph
        (A3A_fnc_computeSupplyGraph), so they can neither be supplied nor relay
        supply. They keep paying their vanilla income untouched.
      - Tier 1+ sites join the graph and, if connected, ship BAR material
        (factories) and earn the tier multiplier on their income contribution.

Arguments:
    None

Return Value:
    <HASHMAP> marker -> tier. Also published as A3A_siteTiers.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    resourcesX, factories, sidesX, destroyedSites, teamPlayer  (globals)
    A3A_fnc_garrisonVehicleRadius
*/

if (!isServer) exitWith {
    Error("Server-only function miscalled");
    missionNamespace getVariable ["A3A_siteTiers", createHashMap]
};

#define TIER_WAREHOUSE_CLASSES ["a3a_warehouse", "Land_Warehouse_03_F"]
#define TIER_GENERATOR_CLASS "Land_PowerGenerator_F"

private _tiers = createHashMap;

private _sites = (missionNamespace getVariable ["resourcesX", []])
               + (missionNamespace getVariable ["factories", []]);

// One scan of each class for the whole map, rather than a nearObjects call per
// site: there are only ever a handful of these, and the site count is not.
private _warehouses = ((allMissionObjects "a3a_warehouse") + (allMissionObjects "Land_Warehouse_03_F")) select { alive _x };
private _generators = (allMissionObjects TIER_GENERATOR_CLASS) select { alive _x };


{
    private _marker = _x;
    if (_marker in destroyedSites) then { continue };
    if !((sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer) then { continue };

    private _pos = getMarkerPos _marker;
    if (_pos isEqualTo [0,0,0]) then { continue };

    // The marker's own extent, floored at 150 m. The floor matters: the upgrade
    // container places its warehouse within 50 m of itself, so a container set
    // down near the edge of a small marker can legitimately put the building
    // just outside the marker. Detecting only inside the marker would leave the
    // player staring at a finished warehouse that the mission refuses to accept.
    private _radius = ([_marker] call A3A_fnc_garrisonVehicleRadius) max 150;

    private _garrison = A3A_garrison getOrDefault [_marker, []];
    private _garrisonObjects = if (_garrison isNotEqualTo []) then {
        (_garrison getOrDefault ["buildings", []]) + (_garrison getOrDefault ["vehicles", []])
    } else { [] };

    private _hasWarehouse = false;
    if (_garrisonObjects findIf { (_x#0) in TIER_WAREHOUSE_CLASSES } >= 0) then {
        _hasWarehouse = true;
    } else {
        if (-1 != _warehouses findIf { (_x distance2D _pos) <= _radius }) then {
            _hasWarehouse = true;
        } else {
            _hasWarehouse = -1 != A3A_buildingsToSave findIf {
                alive _x && { (_x distance2D _pos) <= _radius } && { (typeOf _x) in TIER_WAREHOUSE_CLASSES }
            };
        };
    };

    if (!_hasWarehouse) then { continue };

    private _hasGenerator = false;
    if (_garrisonObjects findIf { (_x#0) == TIER_GENERATOR_CLASS } >= 0) then {
        _hasGenerator = true;
    } else {
        if (-1 != _generators findIf { (_x distance2D _pos) <= _radius }) then {
            _hasGenerator = true;
        } else {
            _hasGenerator = -1 != A3A_buildingsToSave findIf {
                alive _x && { (_x distance2D _pos) <= _radius } && { (typeOf _x) == TIER_GENERATOR_CLASS }
            };
        };
    };

    _tiers set [_marker, [1, 2] select _hasGenerator];


} forEach _sites;

A3A_siteTiers = _tiers;
publicVariable "A3A_siteTiers";

private _dbgCount = count _tiers;
Debug_2("siteTiers: %1 upgraded sites of %2 resource/factory markers", _dbgCount, count _sites);

_tiers
