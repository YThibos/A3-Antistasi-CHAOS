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

  // Tune the influence overlap ceiling live (defaults 1 and 0.05; sane ranges
  // 0.05..100 and 0..1). Both are in the staleness signature, so the overlay
  // picks a change up within 2 seconds of a map being drawn - no force needed.
  A3A_influenceCap = 0.6; A3A_influenceCapTail = 0.15;
  A3A_influenceCap = nil; A3A_influenceCapTail = nil;   // back to the defaults

  // Tune the weight of the faint long cone that closes gaps between distant
  // holdings (default 0.05, sane range 0..0.5; 0 switches it off). Its REACH is
  // the "Territory reach into empty ground" setting, not this. Also in the
  // staleness signature.
  A3A_influenceTailWeight = 0.02;
  A3A_influenceTailWeight = nil;                        // back to the default

  // Re-arm the vanilla map attach on the next map open:
  uiNamespace setVariable ["A3A_influenceMapCtrl", controlNull];

  // Inspect the vanilla map control right now (must be run with the map open):
  private _c = findDisplay 12 displayCtrl 51;
  systemChat format ["ctrl51: null=%1 type=%2", isNull _c, ctrlType _c];
*/

params [["_forceRecompute", false, [false]]];

if (_forceRecompute) then { [true] call A3A_fnc_refreshInfluenceZones };

private _mapCtrl  = uiNamespace getVariable ["A3A_influenceMapCtrl", controlNull];
private _sides    = missionNamespace getVariable "A3A_influenceSides";
private _shapes   = missionNamespace getVariable "A3A_influenceShapes";

private _segTotal = 0;
private _triTotal = 0;
private _perSide  = "no cache";
if (!isNil "_sides") then {
    private _bits = [];
    {
        _x params ["_rgb", "_segments", "_tris"];
        _segTotal = _segTotal + count _segments;
        _triTotal = _triTotal + (count _tris) / 3;
        _bits pushBack format ["[%1,%2,%3] %4 seg / %5 tri",
            (_rgb # 0) toFixed 2, (_rgb # 1) toFixed 2, (_rgb # 2) toFixed 2,
            count _segments, (count _tris) / 3];
    } forEach _sides;
    _perSide = _bits joinString "  ";
};

private _lines = [
    "=== INFLUENCE OVERLAY ===",
    format ["Client init done   : %1", !isNil "A3A_influenceOverlayInit"],
    format ["Vanilla map handler: %1", ["not attached", "attached"] select (!isNull _mapCtrl)],
    format ["Attach retry armed : %1", uiNamespace getVariable ["A3A_influenceAttaching", false]],
    format ["Zone data ready    : %1", !isNil "markersX" && {!isNil "sidesX"} && {!isNil "outpostsFIA"}],
    format ["Sides drawn        : %1", if (isNil "_sides") then { "no cache" } else { count _sides }],
    format ["Per side           : %1", _perSide],
    format ["Border segments    : %1", if (isNil "_sides") then { "no cache" } else { _segTotal }],
    format ["Fill triangles     : %1", if (isNil "_sides") then { "no cache" } else { _triTotal }],
    format ["Claim areas        : %1", if (isNil "_shapes") then { "no cache" } else { count _shapes }],
    format ["Grid cell size     : %1 m", round (missionNamespace getVariable ["A3A_influenceCellSize", -1])],
    format ["Server revision    : %1", missionNamespace getVariable ["A3A_influenceZonesRev", "not received"]],
    format ["Overlay enabled    : %1", missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]],
    format ["Claim areas shown  : %1", missionNamespace getVariable ["A3A_CHAOS_influenceShowClaimAreas", true]],
    format ["Influence range    : %1 m", missionNamespace getVariable ["A3A_CHAOS_influenceRange", 800]],
    format ["Reach / weight     : %1 x range / %2", missionNamespace getVariable ["A3A_CHAOS_influenceReach", "2.0 (default)"], missionNamespace getVariable ["A3A_influenceTailWeight", "0.05 (default)"]],
    format ["Border thickness   : %1 px", missionNamespace getVariable ["A3A_CHAOS_influenceThickness", 4]],
    format ["Fill / opacity     : %1 / %2", missionNamespace getVariable ["A3A_CHAOS_influenceFill", false], missionNamespace getVariable ["A3A_CHAOS_influenceFillOpacity", 0.25]],
    format ["Rebel training     : skillFIA %1 / 20 (scales Guerilla radii only)", missionNamespace getVariable ["skillFIA", "unknown"]],
    format ["Overlap cap / tail : %1 / %2", missionNamespace getVariable ["A3A_influenceCap", "1 (default)"], missionNamespace getVariable ["A3A_influenceCapTail", "0.05 (default)"]],
    format ["War tier / HQ area : %1 / %2 m", missionNamespace getVariable ["tierWar", "unknown"], (markerSize "Synd_HQ") # 0]
];

Info_1("%1", _lines joinString " | ");
["Influence overlay", _lines joinString "<br/>"] call A3A_fnc_customHint;
