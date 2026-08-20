#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Diagnostic dump for the influence zone map overlay.
    Prints a full status report to the RPT log AND to a screen hint.
    Optionally forces a data recompute before reporting.

Arguments:
    [<BOOL> Force recompute before reporting (optional, default false)]

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No

Debug console usage (Escape → Debug console → Local Exec):

  // Full diagnostic report:
  [] call A3A_fnc_debugMapOverlay;

  // Force recompute first, then report:
  [true] call A3A_fnc_debugMapOverlay;

  // Re-run zone computation manually (must have markersX available):
  [] call A3A_fnc_computeInfluenceZones;
  hint format ["Ellipses: %1   Triangles: %2",
      if (!isNil "A3A_influenceEllipses") then {count A3A_influenceEllipses} else {-1},
      if (!isNil "A3A_influenceTriangles") then {count A3A_influenceTriangles} else {-1}];

  // Force the vanilla map Draw EH to be re-attached on next map open:
  A3A_influenceDrawEH = nil;

  // Full reinitialise (clears PFH + EH then re-registers):
  if (!isNil "A3A_influenceOverlayPFH") then {
      [A3A_influenceOverlayPFH] call CBA_fnc_removePerFrameHandler;
  };
  A3A_influenceOverlayPFH = nil;
  A3A_influenceDrawEH = nil;
  [] call A3A_fnc_initMapOverlay;
  hint "Map overlay reinitialised — open the map to reattach the Draw EH";

  // Signal a data refresh without waiting for the next resource tick:
  A3A_influenceZonesDirty = true;

  // Manually check what display 12 ctrl 51 is right now:
  private _c = findDisplay 12 displayCtrl 51;
  hint format ["ctrl51: null=%1  type=%2", isNull _c, ctrlType _c];
*/

params [["_forceRecompute", false, [false]]];

if (_forceRecompute && { !isNil "markersX" }) then {
    [] call A3A_fnc_computeInfluenceZones;
};

// ── Gather state ──────────────────────────────────────────────────────────
private _pfhActive    = !isNil "A3A_influenceOverlayPFH";
private _drawEHID     = missionNamespace getVariable ["A3A_influenceDrawEH", -999];
private _mapOpen      = visibleMap;
private _mapCtrl      = findDisplay 12 displayCtrl 51;
private _ctrlNull     = isNull _mapCtrl;
private _ctrlType     = if (!_ctrlNull) then { ctrlType _mapCtrl } else { -1 };
private _markersReady = !isNil "markersX";
private _sidesReady   = !isNil "sidesX";

private _ellCount = if (!isNil "A3A_influenceEllipses")
    then { count A3A_influenceEllipses } else { -1 };
private _triCount = if (!isNil "A3A_influenceTriangles")
    then { count A3A_influenceTriangles } else { -1 };

private _enabled  = missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true];
private _colIdx   = missionNamespace getVariable ["A3A_CHAOS_influenceColour", 0];
private _maxDist  = missionNamespace getVariable ["A3A_CHAOS_influenceTriangleDist", 2000];
private _dirty    = missionNamespace getVariable ["A3A_influenceZonesDirty", false];

// ── Format and display ────────────────────────────────────────────────────
private _lines = [
    "=== MAP OVERLAY DIAGNOSTICS ===",
    format ["  PFH active          : %1", _pfhActive],
    format ["  Draw EH id          : %2 (%1)", ["NOT ATTACHED","attached"] select (_drawEHID >= 0), _drawEHID],
    format ["  Map open (visibleMap): %1", _mapOpen],
    format ["  ctrl51 null/type    : null=%1  ctrlType=%2 (101=map)", _ctrlNull, _ctrlType],
    format ["  markersX ready      : %1", _markersReady],
    format ["  sidesX ready        : %1", _sidesReady],
    format ["  Ellipses cached     : %1", _ellCount],
    format ["  Triangles cached    : %1", _triCount],
    format ["  Overlay enabled     : %1", _enabled],
    format ["  Colour index        : %1", _colIdx],
    format ["  Triangle max dist   : %1 m", _maxDist],
    format ["  Dirty flag          : %1", _dirty],
    "================================"
];

private _msg = _lines joinString "\n";
Info_1("%1", _msg);
hint _msg;

