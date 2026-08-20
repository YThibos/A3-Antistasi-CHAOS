#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    One-shot initialiser for the vanilla M-map influence zone overlay.
    Called (not spawned) from fn_initClient on every interface client.

    IMPORTANT: findDisplay 12 displayCtrl 51 returns controlNull when the
    vanilla map is closed — the map control is lazily created on first open.
    Therefore ctrlAddEventHandler is deferred into the CBA PFH and runs on the
    first frame that visibleMap transitions false→true.  The Y-menu dialog maps
    (commander, fast-travel, garrison) are also wired in fn_mainDialog /
    fn_hqDialog so the overlay works there regardless of vanilla map status.

    Flow:
      1. Registers a publicVariableEventHandler so the server resource-tick
         broadcast (A3A_influenceZonesDirty = true) triggers a data refresh.
      2. Installs a 0-delay CBA per-frame handler.
         Each frame:
           a. If map just opened: attach the Draw EH on display 12 ctrl 51
              (valid now that the control exists) and compute zone data.
           b. If map open and dirty flag set: recompute zone data.
         No sleep / waitUntil — the EH callback is unscheduled.

    Debug console commands (paste into Escape → Debug console):
      [] call A3A_fnc_debugMapOverlay;              // full diagnostic report
      [true] call A3A_fnc_debugMapOverlay;          // + force recompute
      A3A_influenceZonesDirty = true;               // force refresh on next frame
      A3A_influenceDrawEH = nil; A3A_influenceOverlayPFH = nil;
          [] call A3A_fnc_initMapOverlay;            // full reinit

Arguments:
    None

Return Value:
    None

Scope: Client (interface only)
Environment: Unscheduled (PFH callback is also unscheduled)
Public: No
Dependencies:
    A3A_fnc_computeInfluenceZones (core)
    A3A_GUI_fnc_mapDrawInfluenceEH (gui)
    A3A_influenceZonesDirty (global, written by server resource tick)
*/

// Guard: safe to call multiple times (e.g., debug reinit)
if (!isNil "A3A_influenceOverlayPFH") exitWith {};

// ── 1. Server dirty-flag PVEH ─────────────────────────────────────────────
"A3A_influenceZonesDirty" addPublicVariableEventHandler {
    A3A_influenceZonesDirty = true;
};

// ── 2. CBA per-frame handler (0-delay = every frame) ─────────────────────
// When the map is closed the only cost is two boolean reads per frame.
// _args = [wasMapOpen]
A3A_influenceOverlayPFH = [
    {
        params ["_args"];
        private _isOpen = visibleMap;
        private _wasOpen = _args # 0;
        _args set [0, _isOpen];

        if (!_isOpen) exitWith {};    // map closed — nothing to do this frame

        // ── Map is open ───────────────────────────────────────────────────
        if (!_wasOpen) then {
            // First frame after map opened.
            // The vanilla map control (display 12, ctrl 51) is now valid;
            // attach the Draw EH exactly once for the session.
            if (isNil "A3A_influenceDrawEH") then {
                private _mapCtrl = findDisplay 12 displayCtrl 51;
                if (isNull _mapCtrl) then {
                    Error("initMapOverlay: visibleMap=true but displayCtrl 51 is null — check for mod conflicts");
                } else {
                    A3A_influenceDrawEH = _mapCtrl ctrlAddEventHandler
                        ["Draw", "_this call A3A_GUI_fnc_mapDrawInfluenceEH"];
                    Info_1("initMapOverlay: vanilla map Draw EH attached (id=%1)", A3A_influenceDrawEH);
                };
            };
            // Compute fresh data on every map-open
            A3A_influenceZonesDirty = false;
            [] call A3A_fnc_computeInfluenceZones;
        } else {
            // Map was already open — only recompute if resource tick flagged stale data
            if (missionNamespace getVariable ["A3A_influenceZonesDirty", false]) then {
                A3A_influenceZonesDirty = false;
                [] call A3A_fnc_computeInfluenceZones;
            };
        };
    },
    0,          // 0-delay: every frame (cost = 2 bool reads when map is closed)
    [[false]]   // args: [wasMapOpen]
] call CBA_fnc_addPerFrameHandler;

