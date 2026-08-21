#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Resizes the "Synd_HQ" area marker so that it always matches the current HQ
    build radius (A3A_fnc_hqBuildRadius, 75 m at war tier 1 growing to 210 m at
    war tier 10).

    ---- Why the marker and not a per-call-site check ------------------------
    "Synd_HQ" is an ELLIPSE area marker and every "does this belong to the HQ"
    rule in the codebase is an inArea test against it:

      fn_getMarkerForPos        which garrison claims a placed static / vehicle
      fn_rebelVehPlacedWorker   whether a parked vehicle joins the HQ garrison
      fn_buildHQ                which buildings and vehicles move with the HQ

    Resizing the marker therefore moves all of them at once and keeps them
    consistent by construction, instead of scattering copies of the radius rule.
    It also makes the map overlay's HQ ring follow the same number for free: the
    overlay draws every marker in its own shape and size.

    setMarkerSize is a global command, so the new size reaches every client and
    every player who joins later. Nothing new is saved: the size is derived from
    tierWar, which is already persisted, and is re-applied at server init.

    Call it whenever tierWar can have changed (fn_tierCheck) and once during
    server init after the save data has been loaded.

    Known wrinkle: markersX is sorted by ascending marker size once, in
    fn_initZones, and fn_getMarkerForPos relies on that order to return the
    smallest containing marker. A grown HQ is no longer in its sorted position,
    so if the HQ ever sat inside a zone marker between 75 m and its current
    radius, the HQ would now win the tie. Re-sorting the published markersX at
    runtime is a much bigger change than that edge case is worth.

Arguments:
    None

Return Value:
    <NUMBER> The radius applied, in metres. -1 if nothing was done.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_hqBuildRadius, tierWar (global), the "Synd_HQ" marker
*/

if (!isServer) exitWith { -1 };

// initServer creates the marker long before initVarServer declares tierWar, so
// both can legitimately be missing on an early call.
if (isNil "tierWar") exitWith { -1 };
if ((markerShape "Synd_HQ") isEqualTo "") exitWith { -1 };

private _radius = call A3A_fnc_hqBuildRadius;
private _size = markerSize "Synd_HQ";
if ((_size # 0) isEqualTo _radius && {(_size # 1) isEqualTo _radius}) exitWith { _radius };

"Synd_HQ" setMarkerSize [_radius, _radius];
Debug_1("updateHQMarkerRadius: HQ area marker resized to %1 m", _radius);
_radius
