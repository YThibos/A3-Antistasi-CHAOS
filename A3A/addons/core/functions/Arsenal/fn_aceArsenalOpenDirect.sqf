#include "..\..\script_component.hpp"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"
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

// Ensure event handlers and sorts are initialized
[] call A3A_fnc_aceArsenalInit;

// Save baseline loadout snapshot
A3A_aceArsenal_initialLoadout = getUnitLoadout _unit;
A3A_aceArsenal_activeBox = _target;
A3A_aceArsenal_isOpen = true;

// Build fast stock lookup maps for UI decorations and sorting
A3A_aceArsenal_stockMap = createHashMap;
A3A_aceArsenal_magMap = createHashMap;

if (!isNil "jna_dataList") then {
    {
        private _tabIndex = _forEachIndex;
        private _isMagTab = (_tabIndex == IDC_RSCDISPLAYARSENAL_TAB_CARGOMAGALL);
        {
            _x params ["_item", "_count"];
            if (_item != "") then {
                private _lower = toLowerANSI _item;
                A3A_aceArsenal_stockMap set [_lower, _count];
                if (_isMagTab) then {
                    A3A_aceArsenal_magMap set [_lower, _count];
                };
            };
        } forEach _x;
    } forEach jna_dataList;
};

// Get available items from jna_dataList
private _availableItems = [_target, _unit] call A3A_fnc_aceArsenalGetAvailable;

// Clear previous virtual items on target box and add newly computed available items
[_target, true, false] call ace_arsenal_fnc_removeVirtualItems;
[_target, _availableItems, false] call ace_arsenal_fnc_addVirtualItems;

// Open ACE Arsenal display
[_target, _unit] call ace_arsenal_fnc_openBox;
