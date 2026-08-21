#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Diagnostic dump for the zone-of-influence map overlay. Writes a status
    report to the RPT log and shows the same report in the notification box.
    Optionally forces a recompute first.

Arguments:
    0: <BOOL> Force a recompute before reporting. (optional, default false)

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No

Debug console usage (Escape -> Debug console -> Local Exec):

  // Status report:
  [] call A3A_fnc_debugMapOverlay;

  // Force a recompute first, then report:
  [true] call A3A_fnc_debugMapOverlay;

  // Force a recompute on its own:
  [true] call A3A_fnc_refreshInfluenceZones;

  // Re-arm the vanilla map attach on the next map open:
  uiNamespace setVariable ["A3A_influenceMapCtrl", controlNull];

  // Inspect the vanilla map control right now (must be run with the map open):
  private _c = findDisplay 12 displayCtrl 51;
  systemChat format ["ctrl51: null=%1 type=%2", isNull _c, ctrlType _c];
*/

params [["_forceRecompute", false, [false]]];

if (_forceRecompute) then { [true] call A3A_fnc_refreshInfluenceZones };

private _mapCtrl  = uiNamespace getVariable ["A3A_influenceMapCtrl", controlNull];
private _border   = missionNamespace getVariable "A3A_influenceBorder";
private _shapes   = missionNamespace getVariable "A3A_influenceShapes";

private _lines = [
    "=== INFLUENCE OVERLAY ===",
    format ["Client init done   : %1", !isNil "A3A_influenceOverlayInit"],
    format ["Vanilla map handler: %1", ["not attached", "attached"] select (!isNull _mapCtrl)],
    format ["Attach retry armed : %1", uiNamespace getVariable ["A3A_influenceAttaching", false]],
    format ["Zone data ready    : %1", !isNil "markersX" && {!isNil "sidesX"} && {!isNil "outpostsFIA"}],
    format ["Border segments    : %1", if (isNil "_border") then { "no cache" } else { count _border }],
    format ["Claim areas        : %1", if (isNil "_shapes") then { "no cache" } else { count _shapes }],
    format ["Grid cell size     : %1 m", round (missionNamespace getVariable ["A3A_influenceCellSize", -1])],
    format ["Server revision    : %1", missionNamespace getVariable ["A3A_influenceZonesRev", "not received"]],
    format ["Overlay enabled    : %1", missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]],
    format ["Claim areas shown  : %1", missionNamespace getVariable ["A3A_CHAOS_influenceShowClaimAreas", true]],
    format ["Colour index       : %1", missionNamespace getVariable ["A3A_CHAOS_influenceColour", 0]],
    format ["Link distance      : %1 m", missionNamespace getVariable ["A3A_CHAOS_influenceLinkDist", 2000]]
];

Info_1("%1", _lines joinString " | ");
["Influence overlay", _lines joinString "<br/>"] call A3A_fnc_customHint;
