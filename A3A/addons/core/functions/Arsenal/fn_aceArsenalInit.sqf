#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Initializes ACE Arsenal event handlers on client.

Scope: Client
Environment: Unscheduled
Public: No
*/
if (!hasInterface) exitWith {};
if (missionNamespace getVariable ["A3A_aceArsenal_initialized", false]) exitWith {};
A3A_aceArsenal_initialized = true;

// Register CBA event handler for when ACE Arsenal closes
["ace_arsenal_displayClosed", {
    [] call A3A_fnc_aceArsenalClose;
}] call CBA_fnc_addEventHandler;

Info("ACE Arsenal client event handlers initialized");
