#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    BAR Persistency hook — registered as Persistency_fnc_removeObject so that
    BuildAndRessources calls it when a placed object is demolished.

    BAR's call site (fn_deleteObject.sqf):
        deleteVehicle _target;
        ...
        if (!isNil "Persistency_fnc_removeObject") then {
            [_target] remoteExecCall ["Persistency_fnc_removeObject", 2];
        };

    IMPORTANT: deleteVehicle is called globally BEFORE this hook runs.
    By the time the server processes this remoteExecCall the object is already
    objNull, so we cannot identify it by reference.

    Instead we perform an eager null-filter on A3A_barBuiltObjects here.
    fn_barSave also filters at save time for any entries missed between demolitions.

Arguments:
    0: <OBJECT>  The demolished object — will be objNull by the time this runs.

Return Value:
    <nil>

Scope:       Server
Environment: Unscheduled (via remoteExecCall from client)
Public:      No  — BAR-internal hook only
*/
if (!isServer) exitWith {};
if (isNil "A3A_barBuiltObjects") exitWith {};

private _before = count A3A_barBuiltObjects;
A3A_barBuiltObjects = A3A_barBuiltObjects select { !isNull _x };

Debug_2("barRemoveObject: A3A_barBuiltObjects cleaned from %1 to %2 entr(ies)",
    _before, count A3A_barBuiltObjects);

