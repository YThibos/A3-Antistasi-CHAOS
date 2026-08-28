#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Central wrapper to open the arsenal. Routes to ACE Arsenal or JNA based on
    the chaos_arsenal_useAce CBA setting.

Scope: Client
Environment: Scheduled / Unscheduled
Public: Yes

Params (Standard addAction or direct call):
    0: OBJECT - Target object (default: boxX / jna_object)
    1: OBJECT - Caller (default: player)
    2: SCALAR - Action ID (optional)
    3: ARRAY  - Arguments (optional)
*/
params [
    ["_target", objNull, [objNull]],
    ["_caller", player, [objNull]],
    ["_actionId", -1],
    ["_params", []]
];

if (isNull _target) then {
    _target = missionNamespace getVariable ["jna_object", objNull];
    if (isNull _target && {!isNil "boxX"}) then { _target = boxX };
};

if (isNull _caller) then { _caller = player };

private _useAce = missionNamespace getVariable ["chaos_arsenal_useAce", false];

if (_useAce && {A3A_hasACE} && {!isNil "ace_arsenal_fnc_openBox"}) then {
    [_target, _caller] call A3A_fnc_aceArsenalOpen;
} else {
    if (_useAce && (!A3A_hasACE || isNil "ace_arsenal_fnc_openBox")) then {
        [localize "STR_A3A_feedback_serverinfo", "ACE Arsenal is enabled in settings but ACE3 is not loaded. Falling back to JNA."] call A3A_fnc_customHint;
    };
    _this call JN_fnc_arsenal_handleAction;
};
