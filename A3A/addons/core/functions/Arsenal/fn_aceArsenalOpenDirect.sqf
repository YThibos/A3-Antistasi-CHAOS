#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Populates virtual items and opens ACE Arsenal display.

Scope: Client
Environment: Scheduled
Public: No

Params:
    0: OBJECT - Target container
    1: OBJECT - Unit (player)
*/
params [["_target", objNull, [objNull]], ["_unit", player, [objNull]]];

if (isNull _target) then {
    _target = missionNamespace getVariable ["jna_object", boxX];
};
if (isNull _unit) then { _unit = player };

// Save baseline loadout snapshot
A3A_aceArsenal_initialLoadout = getUnitLoadout _unit;
A3A_aceArsenal_activeBox = _target;
A3A_aceArsenal_isOpen = true;

// Get available items from jna_dataList
private _availableItems = [_target, _unit] call A3A_fnc_aceArsenalGetAvailable;

// Clear previous virtual items on target box and add newly computed available items
[_target, true, false] call ace_arsenal_fnc_removeVirtualItems;
[_target, _availableItems, false] call ace_arsenal_fnc_addVirtualItems;

// Open ACE Arsenal display
[_target, _unit] call ace_arsenal_fnc_openBox;
