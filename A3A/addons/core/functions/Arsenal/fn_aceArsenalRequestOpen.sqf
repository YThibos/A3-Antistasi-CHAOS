#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Server-side request handler for opening ACE Arsenal.

Scope: Server
Environment: Unscheduled
Public: No

Params:
    0: SCALAR - Client Owner ID
    1: OBJECT - Target container
*/
if (!isServer) exitWith {};
params [["_clientOwner", 2, [0]], ["_target", objNull, [objNull]]];

private _playersInArsenal = server getVariable ["jna_playersInArsenal", []];
_playersInArsenal pushBackUnique _clientOwner;
server setVariable ["jna_playersInArsenal", _playersInArsenal, true];

[_target, jna_dataList] remoteExecCall ["A3A_fnc_aceArsenalOpenClient", _clientOwner];
