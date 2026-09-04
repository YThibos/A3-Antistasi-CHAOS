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

    Note the consequence, which corrects RESEARCH.md 2.4.3: blowing up your own
    warehouse does NOT drop the site to Tier 0. It cannot, because upstream
    keeps destroyed garrison buildings in the record and rebuilds them intact
    on the next spawn cycle - the structure genuinely comes back. Tier follows
    the record, which follows the game.

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
    private _entries = (_garrison getOrDefault ["buildings", []])
                     + (_garrison getOrDefault ["vehicles", []]);
    if (_entries isEqualTo []) then { continue };

    if (_entries findIf { (_x # 0) in TIER_WAREHOUSE_CLASSES } < 0) then { continue };

    private _hasGenerator = (_entries findIf { (_x # 0) isEqualTo TIER_GENERATOR_CLASS }) >= 0;
    _tiers set [_marker, [1, 2] select _hasGenerator];

} forEach _sites;

A3A_siteTiers = _tiers;
publicVariable "A3A_siteTiers";

Debug_2("siteTiers: %1 upgraded sites of %2 resource/factory markers", count _tiers, count _sites);

_tiers
