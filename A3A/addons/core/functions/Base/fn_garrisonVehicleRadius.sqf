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
          Fixed 30 m circle around the marker centre. fn_getMarkerForPos uses
          outpostsFIA inAreaArrayIndexes [_pos, 30, 30], and inAreaArrayIndexes
          treats the area as an ellipse unless its isRectangle argument is set,
          which it is not. That matches the marker itself, created as an ELLIPSE
          of size [30, 30] in fn_createRebelControl.

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
             Watchpost / roadblock, or no marker given : always 30.
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
// Fixed 30 m circle. This constant is also the exact size the marker is created
// with (fn_createRebelControl: _marker setMarkerSizeLocal [30,30]).
if (_marker isEqualTo "") exitWith { 30 };
if (!isNil "outpostsFIA" && {_marker in outpostsFIA}) exitWith { 30 };

// ---- All other garrison markers --------------------------------------------
// Coarse extent only - the authoritative test for these is inArea.
private _size = markerSize _marker;
(_size # 0) max (_size # 1)
