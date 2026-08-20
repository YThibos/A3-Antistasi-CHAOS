#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    One-shot initialiser for the vanilla M-map influence zone overlay.
    Called (not spawned) from fn_initClient on every interface client.

    Flow:
      1. Attaches A3A_GUI_fnc_mapDrawInfluenceEH as a permanent Draw EH on the
         vanilla map control (display 12, control 51) via isNil{} so that
         findDisplay and ctrlAddEventHandler run in unscheduled context, which is
         required for reliable UI operations from an init function that may itself
         be reached from scheduled code.
      2. Registers a publicVariableEventHandler so the server's resource-tick
         broadcast (A3A_influenceZonesDirty = true) triggers a recompute.
      3. Installs a CBA per-frame handler (1-second interval, no sleep/waitUntil)
         that detects map-open transitions and dirty-flag signals, then calls
         A3A_fnc_computeInfluenceZones to refresh the cached draw data.

Arguments:
    None

Return Value:
    None

Scope: Client (interface only)
Environment: Unscheduled (called; isNil{} inner block also unscheduled)
Public: No
Dependencies:
    A3A_fnc_computeInfluenceZones (core)
    A3A_GUI_fnc_mapDrawInfluenceEH (gui)
    A3A_influenceZonesDirty (global, written by server resource tick)
*/

// Guard: safe to call multiple times (e.g., JIP reconnect)
if (!isNil "A3A_influenceOverlayPFH") exitWith {};

// ── 1. Attach the Draw EH once ────────────────────────────────────────────
// isNil{} forces unscheduled context so findDisplay/ctrlAddEventHandler work
// correctly even if initClient reaches here through scheduled code.
isNil {
    private _mapCtrl = findDisplay 12 displayCtrl 51;
    if (isNull _mapCtrl) exitWith {
        Error("initMapOverlay: findDisplay 12 displayCtrl 51 returned null — vanilla map overlay disabled");
    };
    // Use a string handler, matching the pattern used by all other map Draw EHs
    _mapCtrl ctrlAddEventHandler ["Draw", "_this call A3A_GUI_fnc_mapDrawInfluenceEH"];
    Info("initMapOverlay: Draw EH attached to vanilla map control (display 12 ctrl 51)");
};

// ── 2. Server dirty-flag PVEH ─────────────────────────────────────────────
// Resource tick (every 10 min) broadcasts this; the PFH below picks it up.
"A3A_influenceZonesDirty" addPublicVariableEventHandler {
    A3A_influenceZonesDirty = true;
};

// ── 3. CBA per-frame handler — map-open detection + data refresh ──────────
// Fires at most once per second; no sleep or waitUntil in the callback.
// _args#0 = was the map open on the previous check?
A3A_influenceOverlayPFH = [
    {
        params ["_args"];
        private _isOpen = visibleMap;
        private _wasOpen = _args # 0;
        _args set [0, _isOpen];

        // Recompute when the map just opened, or when open and data is stale
        if (_isOpen && { !_wasOpen || missionNamespace getVariable ["A3A_influenceZonesDirty", false] }) then {
            A3A_influenceZonesDirty = false;
            [] call A3A_fnc_computeInfluenceZones;
        };
    },
    1,          // at most once per second — cheap boolean checks only
    [[false]]   // args: [wasMapOpen]
] call CBA_fnc_addPerFrameHandler;

