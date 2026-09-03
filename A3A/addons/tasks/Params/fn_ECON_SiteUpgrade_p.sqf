#include "..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Picks the site for a CHAOS site upgrade mission, and which upgrade it is.

    ---- No distance limit from HQ ------------------------------------------
    Every other task params function weights or filters targets by
    `distanceMission` from the HQ. This one deliberately does NOT. The whole
    point of the logistics arc is that you settle into a fixed HQ once the base
    is worth defending; if upgrade missions only ever appeared near it, a
    settled HQ would starve of them and the player would be pushed to relocate
    late game to keep the economy growing - the exact opposite of the intended
    story. Reach is the supply graph's job, not the mission picker's.

    Distance still shapes the pick, but only as a mild preference for closer
    sites, never as a cutoff: a far mine is a worse first choice than a near
    one, and is still eventually offered.

    ---- What it picks ------------------------------------------------------
    Tier 0 sites are weighted well above Tier 1 sites, so the campaign spreads
    warehouses across the map before it starts adding generators. Within a tier,
    factories outweigh resources, because a factory's upgrade multiplies the
    whole cash sum while a resource's only adds to it.

Arguments:
    None

Return Value:
    <ARRAY> [1, [_marker, _tier]] where _tier is the tier being built TOWARD
            (1 = supply warehouse, 2 = power generator).
    <BOOL>  false when there is no eligible site.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    resourcesX, factories, sidesX, destroyedSites, teamPlayer, spawner
    A3A_fnc_siteTiers
*/

private _tiers = call A3A_fnc_siteTiers;
private _hqPos = markerPos "Synd_HQ";

private _weighted = [];
{
    private _marker = _x;
    if (_marker in destroyedSites) then { continue };
    if !((sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer) then { continue };

    // NO spawner guard. An earlier version skipped markers whose spawner state was
    // not 0, believing 0 meant "quiet". It is the opposite: fn_distance defines
    // ENABLED 0 / DISABLED 1, and fn_initZones seeds every marker at 2, so 0 means
    // the marker is currently SPAWNED IN around a player. The guard therefore
    // rejected every site that was not loaded at that moment, which in practice is
    // nearly all of them, and Petros always answered "nothing to develop".
    //
    // There is no guard here now because there is nothing to guard against: the
    // site is already ours, and whether it happens to be rendered says nothing
    // about whether we can be tasked to upgrade it. The container spawns at HQ
    // either way.

    private _tier = _tiers getOrDefault [_marker, 0];
    if (_tier >= 2) then { continue };                  // fully upgraded

    // Tier 0 first: spread warehouses before adding generators.
    private _tierWeight = [10, 3] select _tier;
    // A factory upgrade multiplies the whole cash sum; a resource upgrade only
    // adds to it, so a factory is the better mission when both are available.
    private _kindWeight = [1, 1.5] select (_marker in factories);

    // Mild distance preference. Never a cutoff - see the header. Bottoms out at
    // 0.35 rather than 0, so the far side of the map stays reachable content.
    private _dist = (markerPos _marker) distance2D _hqPos;
    private _distWeight = linearConversion [1000, 6000, _dist, 1, 0.35, true];

    _weighted append [[_marker, _tier + 1], _tierWeight * _kindWeight * _distWeight];

} forEach (resourcesX + factories);

if (_weighted isEqualTo []) exitWith { false };

[1, [selectRandomWeighted _weighted]]
