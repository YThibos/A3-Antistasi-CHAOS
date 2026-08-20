#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: John Jordan
    Single source of truth for the radius within which a manually placed vehicle
    or static weapon is "claimed" by a garrison marker.

    ── Background ──────────────────────────────────────────────────────────────
    When a player places a static weapon (or uses "Add to garrison" in the context
    menu), fn_getMarkerForPos decides which garrison owns the vehicle based on its
    position.  The rules differ by marker type:

    ┌──────────────────────────────────────────────────────────────────────────┐
    │ Marker type            │ Claim rule          │ Radius                   │
    ├────────────────────────┼─────────────────────┼──────────────────────────┤
    │ Watchpost / Roadblock  │ Fixed square        │ 30 m from marker centre  │
    │ (outpostsFIA)          │ (both axes = 30 m)  │ in each direction        │
    ├────────────────────────┼─────────────────────┼──────────────────────────┤
    │ All other markers      │ Marker ellipse      │ Varies — typically       │
    │ (outposts, airports,   │ (inArea check)      │ 50–600 m depending on    │
    │ factories, seaports,   │                     │ how the marker is drawn  │
    │ rebel HQ, cities)      │                     │ for the mission/map      │
    └──────────────────────────────────────────────────────────────────────────┘

    Watchpost markers are always created with markerSize [30, 30] (see
    fn_createRebelControl), so the 30 m claim square exactly matches the
    marker's visual footprint.

    For all other markers there is no fixed cap: place the static anywhere inside
    the marker ellipse and it will be claimed.  The return value for non-watchpost
    markers is the marker's maximum semi-axis (the largest single-direction
    distance from the centre at which you can still be inside the ellipse along
    that axis); think of it as "the marker's radius" for quick sanity-checking.

    ── Usage in fn_getMarkerForPos ─────────────────────────────────────────────
    The watchpost constant is used as:
        outpostsFIA inAreaArrayIndexes [_pos, _wpRadius, _wpRadius]
    Change it here and it takes effect everywhere.

Arguments:
    <STRING>  Marker name.  Pass any outpostsFIA marker (they all share the same
              fixed radius) or any other garrison marker name.

Return Value:
    <NUMBER>  Claim radius in metres.
              Watchpost/roadblock : always 30.
              Other markers       : max(markerSize#0, markerSize#1)
                                    — the marker's own maximum semi-axis.

Scope: Server / Any
Environment: Unscheduled
Public: No
*/

params [["_marker", "", [""]]];

// ── Watchpost / roadblock (outpostsFIA) ──────────────────────────────────────
// Fixed 30 m square regardless of what the marker visually looks like.
// This constant is also the exact size set when the marker is created
// (fn_createRebelControl: _marker setMarkerSizeLocal [30,30]).
if (_marker in outpostsFIA) exitWith { 30 };

// ── All other garrison markers ────────────────────────────────────────────────
// No hard cap: the vehicle must simply be inside the marker's own ellipse.
// Return the maximum semi-axis as a usable "radius" for callers that need a number.
private _sz = markerSize _marker;
(_sz select 0) max (_sz select 1)

