#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Initialiser for the friendly zone-of-influence map overlay ("borders").
    Safe to call more than once and safe to call on any machine: each half
    guards itself, so the dedicated server runs only the server half, a client
    runs only the client half, and a hosted host runs both.

    Server half - live refresh signal.
    Registers listeners on the existing markerChange, RebelControlCreated and
    HQPlaced events (all of which are triggered server-side) and bumps a public
    revision counter, A3A_influenceZonesRev.  Clients notice the new value on
    their next staleness check and redraw.  There is deliberately no event for
    watchpost/roadblock deletion because the codebase does not fire one;
    A3A_fnc_refreshInfluenceZones catches that case through its signature.

    Client half - attaching the Draw event handler to the vanilla M-map.
    findDisplay 12 displayCtrl 51 is the vanilla map control, and it is created
    lazily: it is controlNull while the map is closed, so the handler cannot be
    attached at init time.  A "Map" mission event handler fires on open/close;
    on open we arm a short-lived CBA per-frame handler that retries the attach
    until the control exists, then removes itself.  Nothing per-frame survives
    once the handler is attached.

    The stored control (A3A_influenceMapCtrl) is the attach guard rather than an
    event-handler id, so if display 12 is ever destroyed and recreated the
    control goes null and the overlay re-attaches itself on the next map open.

    The Y-menu commander / fast-travel / garrison maps attach the same Draw
    event handler from fn_mainDialog / fn_hqDialog and need nothing from here.

Arguments:
    None

Return Value:
    None

Scope: Server and client (call from both fn_initServer and fn_initClient)
Environment: Unscheduled
Public: No
Dependencies:
    A3A_GUI_fnc_mapDrawInfluenceEH
    A3A_Events_fnc_addEventListener
*/

// ---- Server half: publish a revision counter on territory changes -------
if (isServer && {isNil "A3A_influenceZonesRev"}) then {
    A3A_influenceZonesRev = 0;
    publicVariable "A3A_influenceZonesRev";

    private _bump = {
        A3A_influenceZonesRev = A3A_influenceZonesRev + 1;
        publicVariable "A3A_influenceZonesRev";
    };
    ["markerChange", "A3A_influenceOverlay", _bump] call EFUNC(Events,addEventListener);
    ["RebelControlCreated", "A3A_influenceOverlay", _bump] call EFUNC(Events,addEventListener);
    ["HQPlaced", "A3A_influenceOverlay", _bump] call EFUNC(Events,addEventListener);
};

// ---- Client half --------------------------------------------------------
if (!hasInterface) exitWith {};
if (!isNil "A3A_influenceOverlayInit") exitWith {};
A3A_influenceOverlayInit = true;

private _onMapToggle = {
    params ["_mapIsOpened"];
    if (!_mapIsOpened) exitWith {};
    // Already attached to a live control, or an attach attempt is already armed.
    if !(isNull (missionNamespace getVariable ["A3A_influenceMapCtrl", controlNull])) exitWith {};
    if (missionNamespace getVariable ["A3A_influenceAttaching", false]) exitWith {};

    // Set the guard before arming, so the handler is correct even if CBA were
    // to run it immediately.
    A3A_influenceAttaching = true;
    [
        {
            params ["", "_handle"];
            private _mapCtrl = findDisplay 12 displayCtrl 51;
            if (!isNull _mapCtrl) then {
                _mapCtrl ctrlAddEventHandler ["Draw", "_this call A3A_GUI_fnc_mapDrawInfluenceEH"];
                A3A_influenceMapCtrl = _mapCtrl;
                Info("initMapOverlay: influence overlay attached to the vanilla map");
            };
            // Stop retrying once attached, or once the player closed the map again.
            if (!isNull _mapCtrl || {!visibleMap}) then {
                A3A_influenceAttaching = false;
                [_handle] call CBA_fnc_removePerFrameHandler;
            };
        },
        0
    ] call CBA_fnc_addPerFrameHandler;
};

addMissionEventHandler ["Map", _onMapToggle];

// Cover the case where the map is already open when this runs.
if (visibleMap) then { [true] call _onMapToggle };
