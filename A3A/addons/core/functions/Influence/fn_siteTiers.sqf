#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
#include "..\..\Includes\siteTiers.hpp"
/*
Maintainer: Antistasi CHAOS
    Recomputes the CHAOS upgrade tier of every rebel-held resource and factory,
    and publishes the result.

    ---- Tier is DERIVED, never stored -------------------------------------
    A site's tier is read off the structures the site's garrison record says
    stand on it:

        Tier 0  nothing built                       - vanilla behaviour
        Tier 1  a supply warehouse on the site      - a3a_warehouse
        Tier 2  warehouse + power generator         - Land_PowerGenerator_F

    Deriving it rather than storing a number per marker is what keeps this out
    of the save system entirely: the garrison record is already saved and
    reloaded, so the tier persists with it for free.

    ---- Why the GARRISON RECORD and not the world ------------------------
    An earlier version scanned allMissionObjects for the structure classes.
    That is wrong for every site a player is not currently standing in.
    A3A_fnc_garrisonLocal_despawn DELETES a marker's buildings and vehicles
    when the marker despawns, and A3A_fnc_garrisonLocal_spawn recreates them
    from the server-side record on the way back in. Sites are despawned nearly
    all of the time, so a world scan reported Tier 0 for almost every upgraded
    site, and the supply graph flapped every time a player drove past one.

    A3A_garrison is the only representation that is true whether the site is
    spawned, despawned or freshly loaded from a save, so it is the single
    source of truth here. There is deliberately no fallback scan and no
    separate save list: a second source can only ever disagree with the first.

    ---- Destruction has to be written INTO the record ---------------------
    Deriving from the record has one hole, and it is the reason this function
    also reconciles. Upstream never removes a destroyed building from a
    garrison: fn_garrisonLocal_despawn deletes the world objects and
    fn_garrisonLocal_spawn recreates every recorded entry INTACT, so a
    warehouse blown up by the player, by Zeus or by a QRF stayed Tier 1
    forever and came back whole on the next spawn cycle. That survived a save
    too, because A3A_garrison is what the save carries.

    Upstream's own destroyed-building list is no help here: fn_saveLoop stores
    A3A_destroyedBuildings as POSITIONS and fn_loadStat resolves them with
    nearestObjects during load, long before any garrison has spawned, so a
    garrison building is simply not there to be found.

    So before deriving, each recorded tier structure is checked against the
    world and dropped from the record if it is standing there DESTROYED. The
    test is deliberately one-sided: only an object of the recorded class, at
    the recorded position, that is not alive counts as lost. A missing object
    means nothing - it is the normal state of every despawned site - so
    nothing is ever pruned on absence. A false negative costs a stale tier
    until the next pass; a false positive would delete a structure the player
    paid 1500 for, so the check never guesses.

    The ruin does not enter into it. Arma leaves the original object in place
    with damage 1 and adds a separate Ruins object beside it, so the presence
    test still finds the original and simply sees that it is dead.

    A3A_fnc_buildingChangedEH calls this the moment a tier structure is ruined,
    so the record is corrected while the player is still standing there rather
    than at the next income tick.

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
    resourcesX, factories, sidesX, destroyedSites, teamPlayer, A3A_garrison (globals)
*/

if (!isServer) exitWith {
    Error("Server-only function miscalled");
    missionNamespace getVariable ["A3A_siteTiers", createHashMap]
};

private _tiers = createHashMap;

// True only when this record entry names a tier structure that is standing in
// the world DESTROYED. Absence is never destruction: a despawned site has no
// objects at all, and pruning on absence would wipe every tier the moment a
// player drove away.
private _fnc_structureDestroyed = {
    params ["_entry"];

    private _class = _entry # 0;
    if !(_class in TIER_STRUCTURE_CLASSES) exitWith { false };

    // Buildings store the position directly; vehicles wrap it in
    // [posWorld, vecDir, vecUp] - or replace it with a spawn-place index, which
    // a tier structure never has, but which must not be read as a position.
    private _posWorld = _entry # 1;
    if (_posWorld isEqualType [] && {(count _posWorld) > 0} && {(_posWorld # 0) isEqualType []}) then {
        _posWorld = _posWorld # 0;
    };
    if !(_posWorld isEqualType [] && {(count _posWorld) >= 3}) exitWith { false };

    // nearestObject filters by class, so the only thing it can return is a
    // structure of exactly this type - and the nearest one, which is ours.
    private _obj = nearestObject [ASLtoATL _posWorld, _class];
    !isNull _obj && {!alive _obj}
};

private _sites = (missionNamespace getVariable ["resourcesX", []])
               + (missionNamespace getVariable ["factories", []]);

{
    private _marker = _x;
    if (_marker in destroyedSites) then { continue };
    if !((sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer) then { continue };

    private _garrison = A3A_garrison getOrDefault [_marker, createHashMap];

    // Both record formats put the class name at index 0:
    //   buildings  [class, posWorld, vecDir, vecUp]
    //   vehicles   [class, [posWorld, vecDir, vecUp] | spawnPlaceIndex, state, vehID]
    // The warehouse is a building (it is constructed); the generator is a
    // registered utility item, so it files as a vehicle. Read both.
    private _buildings = _garrison getOrDefault ["buildings", []];
    private _vehicles  = _garrison getOrDefault ["vehicles", []];

    // Reconcile first - see the header. getOrDefault hands back the live array,
    // so deleting here edits the record itself, which is what makes the drop
    // survive a despawn/spawn cycle and a save.
    {
        if ([_x] call _fnc_structureDestroyed) then {
            Info_2("siteTiers: destroyed %1 removed from the garrison record of %2", _x # 0, _marker);
            _buildings deleteAt _forEachIndex;
        };
    } forEachReversed _buildings;
    {
        if ([_x] call _fnc_structureDestroyed) then {
            Info_2("siteTiers: destroyed %1 removed from the garrison record of %2", _x # 0, _marker);
            _vehicles deleteAt _forEachIndex;
        };
    } forEachReversed _vehicles;

    private _entries = _buildings + _vehicles;
    if (_entries isEqualTo []) then { continue };

    if (_entries findIf { (_x # 0) in TIER_WAREHOUSE_CLASSES } < 0) then { continue };

    private _hasGenerator = (_entries findIf { (_x # 0) isEqualTo TIER_GENERATOR_CLASS }) >= 0;
    _tiers set [_marker, [1, 2] select _hasGenerator];

} forEach _sites;

A3A_siteTiers = _tiers;
publicVariable "A3A_siteTiers";

Debug_2("siteTiers: %1 upgraded sites of %2 resource/factory markers", count _tiers, count _sites);

_tiers
