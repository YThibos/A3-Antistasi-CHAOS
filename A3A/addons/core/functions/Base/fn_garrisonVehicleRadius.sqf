#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Single source of truth for the radius within which a manually placed vehicle
    or static weapon is "claimed" by a garrison marker.

    ---- Background ------------------------------------------------------------
    When a player places a static weapon (or uses "Add to garrison" in the context
    menu), fn_getMarkerForPos decides which garrison owns the vehicle based on its
    position. The rules differ by marker type:

      Watchpost / roadblock (outpostsFIA)
          Circular area around the marker centre, scaling with war tier (51 m at
          war tier 1 growing to 150 m at war tier 10). fn_getMarkerForPos uses
          outpostsFIA inAreaArrayIndexes [_pos, _wpRadius, _wpRadius], which
          treats the area as an ellipse / circle.

      Everything else (outposts, airports, factories, resources, seaports,
      rebel HQ, cities)
          No fixed radius at all: the real test is _pos inArea _marker, which
          honours the marker's own shape and rotation. Most Antistasi zone
          markers are RECTANGLE, so no single number describes them. The value
          returned here for those markers is the largest semi-axis, useful only
          as a coarse "how big is this zone" figure for range checks and
          overlays - never as a substitute for inArea.

Arguments:
    0: <STRING> Marker name. Omit (or pass "") to ask for the watchpost/roadblock
       constant without naming a specific post. (optional, default "")

Return Value:
    <NUMBER> Claim radius in metres.
             Watchpost / roadblock, or no marker given : 51 m (tier 1) to 150 m (tier 10).
             Any other marker                          : max(markerSize#0, markerSize#1)

Scope: Anywhere
Environment: Unscheduled
Public: No

Example:
    private _wpRadius = [] call A3A_fnc_garrisonVehicleRadius;
    private _zoneReach = ["Synd_HQ"] call A3A_fnc_garrisonVehicleRadius;
*/

params [["_marker", "", [""]]];

// ---- Watchpost / roadblock (outpostsFIA) -----------------------------------
// Circular claim radius scaling with war tier: 51 m at tier 1 to 150 m at tier 10.
//
// This used to be 30 * _tier. Both ends of that were wrong for a RADIUS: 300 m
// at tier 10 claims most of a small valley, while 30 m at tier 1 is smaller than
// many roadblock footprints, so a static parked at the far end of the post
// stopped counting as part of it. 40 + 11 * _tier keeps the sensible cap and
// starts somewhere usable.
if (_marker isEqualTo "" || {!isNil "outpostsFIA" && {_marker in outpostsFIA}}) exitWith {
    private _tier = (missionNamespace getVariable ["tierWar", 1]) max 1 min 10;
    40 + 11 * _tier
};

// ---- All other garrison markers --------------------------------------------
// Coarse extent only - the authoritative test for these is inArea.
private _size = markerSize _marker;
(_size # 0) max (_size # 1)
