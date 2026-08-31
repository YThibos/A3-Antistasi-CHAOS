#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Initializes ACE Arsenal event handlers and sorting on client.

Scope: Client
Environment: Unscheduled
Public: No
*/
if (!hasInterface) exitWith {};
if (missionNamespace getVariable ["A3A_aceArsenal_initialized", false]) exitWith {};
A3A_aceArsenal_initialized = true;

// 1. Register custom Sort by Amount for ACE Arsenal
[
    [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], // Left tabs
        [0, 1, 2, 3, 4, 5, 6, 7]                             // Right tabs
    ],
    "chaos_sort_amount",
    localize "STR_A3A_JNA_sort_amount",
    {
        params ["_itemCfg", "_item", "_quantity"];
        if (isNil "A3A_aceArsenal_stockMap") exitWith { 0 };
        private _stock = A3A_aceArsenal_stockMap getOrDefault [toLowerANSI _item, 0];
        if (_stock == -1) then {
            100000000
        } else {
            _stock
        };
    }
] call ace_arsenal_fnc_addSort;

// 2. Register UI decoration event handlers
["ace_arsenal_leftPanelFilled", {
    params ["_display", "_ctrlIDC", "_currentRightPanel"];
    if (missionNamespace getVariable ["A3A_aceArsenal_isOpen", false]) then {
        [_display, _ctrlIDC] call A3A_fnc_aceArsenalDecorateLeft;
    };
}] call CBA_fnc_addEventHandler;

["ace_arsenal_rightPanelFilled", {
    params ["_display", "_currentLeftPanel", "_ctrlIDC"];
    if (missionNamespace getVariable ["A3A_aceArsenal_isOpen", false]) then {
        [_display, _ctrlIDC] call A3A_fnc_aceArsenalDecorateRight;
    };
}] call CBA_fnc_addEventHandler;

// 3. Register display closed event handler
["ace_arsenal_displayClosed", {
    [] call A3A_fnc_aceArsenalClose;
}] call CBA_fnc_addEventHandler;

Info("ACE Arsenal client event handlers and sorts initialized");
