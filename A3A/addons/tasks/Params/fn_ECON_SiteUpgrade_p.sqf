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

private _candidates = [];
{
    private _marker = _x;
    if (_marker in destroyedSites) then { continue };
    if !((sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer) then { continue };

    private _tier = _tiers getOrDefault [_marker, 0];
    if (_tier >= 2) then { continue };

    private _isFactory = _marker in factories;
    private _dist = (markerPos _marker) distance2D _hqPos;

    _candidates pushBack [_marker, _tier, _isFactory, _dist];

} forEach (resourcesX + factories);

if (_candidates isEqualTo []) exitWith { false };

// Sort by: tier ASC (0 is highest priority), kind (Resources [false] before Factories [true]), distance ASC (closest first).
_candidates = [_candidates, [], {
    _x params ["", "_tier", "_isFactory", "_dist"];
    // _tier * 1000000 ensures tier 0 < tier 1. 
    // Factory adds 100000, so resources are lower value (higher priority).
    // Dist adds the remainder.
    (_tier * 1000000) + ([0, 100000] select _isFactory) + _dist
}, "ASCEND"] call BIS_fnc_sortBy;

private _best = _candidates select 0;
[1, [_best # 0, (_best # 1) + 1]]
