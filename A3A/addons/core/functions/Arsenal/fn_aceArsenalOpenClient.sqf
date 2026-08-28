#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Client-side receiver for server arsenal sync before opening ACE Arsenal.

Scope: Client
Environment: Scheduled
Public: No

Params:
    0: OBJECT - Target container
    1: ARRAY  - Master jna_dataList
*/
if (!hasInterface) exitWith {};
params [["_target", objNull, [objNull]], ["_dataList", [], [[]]]];

"A3A_ArsenalLoading" call BIS_fnc_endLoadingScreen;

if (!(_dataList isEqualTo [])) then {
    jna_dataList = _dataList;
};

[_target, player] call A3A_fnc_aceArsenalOpenDirect;
