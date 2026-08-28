#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Initializes the arsenal system on the specified box or container.
    Sets up JNA data structures as the underlying backend and registers ACE Arsenal hooks.

Scope: Server & Clients
Environment: Unscheduled
Public: Yes

Params:
    0: OBJECT - Target container (e.g., boxX)
*/
params [["_object", objNull, [objNull]]];

if (isNull _object) exitWith {
    Error("initArsenal called with null object");
};

// Always initialize JNA data structures and server variables as the underlying data store
_object call jn_fnc_arsenal_init;

// On client / player interface, register ACE Arsenal display event handlers
if (hasInterface) then {
    [] call A3A_fnc_aceArsenalInit;
};

Info_1("Arsenal initialized for object %1", _object);
