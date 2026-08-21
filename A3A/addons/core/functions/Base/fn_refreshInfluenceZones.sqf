#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Keeps the influence-zone overlay cache fresh without ever recomputing per
    frame.  Called from the top of A3A_GUI_fnc_mapDrawInfluenceEH, so every map
    that draws the overlay (vanilla M-map and the Y-menu commander, fast-travel
    and garrison maps) gets correct data on its very first frame, whatever the
    player opened first.

    Two-stage throttle:
      1. At most one staleness check every 2 seconds
         (wall clock, so it is unaffected by time acceleration).
      2. The check builds a small signature of everything the geometry depends
         on and only calls A3A_fnc_computeInfluenceZones when it changed.

    The signature is derived from the same public data the overlay is drawn
    from, so it self-heals through anything that has no event of its own -
    JIP, save/load, a watchpost being demolished, HQ relocation, a rebel AI
    training upgrade, a war tier change - while the
    server-side revision counter (A3A_influenceZonesRev, bumped from the
    markerChange / RebelControlCreated / HQPlaced events by
    A3A_fnc_initMapOverlay) makes ordinary capture changes show up on the very
    next check instead of waiting for the next full comparison to differ.

Arguments:
    0: <BOOL> Force a recompute, ignoring both throttle and signature. (optional, default false)

Return Value:
    <BOOL> true if a recompute was performed.

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    markersX, outpostsFIA, controlsX, sidesX, teamPlayer   (public globals)
    A3A_fnc_computeInfluenceZones
*/

params [["_force", false, [false]]];

// Zone data not broadcast yet: leave the cache alone and retry on a later frame.
if (isNil "markersX" || {isNil "outpostsFIA"} || {isNil "sidesX"}) exitWith { false };

private _now  = diag_tickTime;
private _last = missionNamespace getVariable ["A3A_influenceCheckTime", -1e7];
private _cached = !isNil "A3A_influenceSignature";

if (!_force && {_cached} && {_now - _last < 2}) exitWith { false };
A3A_influenceCheckTime = _now;

// ---- Signature over everything the geometry depends on ------------------
private _controls = missionNamespace getVariable ["controlsX", []];
private _sides = [];
{
    private _side = sidesX getVariable [_x, sideUnknown];
    // 1 = ours, 2 = someone else's, 0 = not owned / not initialised
    _sides pushBack (if (_side isEqualTo teamPlayer) then { 1 } else { [2, 0] select (_side isEqualTo sideUnknown) });
} forEach (markersX + outpostsFIA + _controls);

private _signature = [
    missionNamespace getVariable ["A3A_CHAOS_influenceRange", 800],
    missionNamespace getVariable ["A3A_CHAOS_influenceFill", false],
    // Rebel AI training scales every influence radius, and there is no event
    // for it - fn_FIAskillAdd only publicVariables skillFIA - so the signature
    // is what catches a training upgrade.
    missionNamespace getVariable ["skillFIA", 1],
    // War tier drives A3A_fnc_hqBuildRadius and therefore the size of the
    // "Synd_HQ" marker (fn_updateHQMarkerRadius), which is the HQ's drawn claim
    // area. It no longer sets the HQ's influence radius - that is a flat 1.25x.
    missionNamespace getVariable ["tierWar", 1],
    missionNamespace getVariable ["A3A_influenceZonesRev", 0],
    getMarkerPos "Synd_HQ",         // HQ is the only marker that moves
    +outpostsFIA,                   // copies: these globals are replaced wholesale on change
    +_controls,
    _sides
];

if (!_force && {(missionNamespace getVariable ["A3A_influenceSignature", []]) isEqualTo _signature}) exitWith { false };

[] call A3A_fnc_computeInfluenceZones;
// Recorded only after the compute ran, so a failed compute is retried
// on the next check instead of being latched as up to date.
A3A_influenceSignature = _signature;
true
