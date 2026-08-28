#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Initiates opening of ACE Arsenal. Requests latest arsenal data if needed
    and opens the interface.

Scope: Client
Environment: Scheduled
Public: No

Params:
    0: OBJECT - Target container (e.g. boxX)
    1: OBJECT - Unit opening arsenal (e.g. player)
*/
params [["_target", objNull, [objNull]], ["_unit", player, [objNull]]];

if (isNull _target) then {
    _target = missionNamespace getVariable ["jna_object", boxX];
};

if (isNull _unit) then { _unit = player };

// Show loading screen
["A3A_ArsenalLoading", "Arsenal"] call BIS_fnc_startLoadingScreen;

if (isServer) then {
    // Local server / singleplayer
    private _playersInArsenal = server getVariable ["jna_playersInArsenal", []];
    _playersInArsenal pushBackUnique clientOwner;
    server setVariable ["jna_playersInArsenal", _playersInArsenal, true];

    "A3A_ArsenalLoading" call BIS_fnc_endLoadingScreen;
    [_target, _unit] call A3A_fnc_aceArsenalOpenDirect;
} else {
    // Remote client: request sync from server
    [clientOwner, _target] remoteExecCall ["A3A_fnc_aceArsenalRequestOpen", 2];
};
