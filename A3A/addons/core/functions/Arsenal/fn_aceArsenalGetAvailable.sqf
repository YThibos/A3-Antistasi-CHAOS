#include "..\..\script_component.hpp"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Returns an array of item classnames currently available in the arsenal for the unit.
    Accounts for unlocked items (-1), in-stock items (> 0), guest limits, and equipped items.

Scope: Client
Environment: Unscheduled
Public: Yes

Params:
    0: OBJECT - Target container
    1: OBJECT - Unit querying available items (default: player)

Returns:
    ARRAY of STRING - Classnames of available virtual items
*/
params [["_target", objNull, [objNull]], ["_unit", player, [objNull]]];

if (isNil "jna_dataList") exitWith { [] };

private _isMember = [_unit] call A3A_fnc_isMember;
private _enforceGuestLimits = missionNamespace getVariable ["chaos_arsenal_enforceGuestLimits", true];
private _availableItems = createHashMap;

// 1. Iterate all categories in jna_dataList
{
    private _tabIndex = _forEachIndex;
    private _isMag = (_tabIndex == IDC_RSCDISPLAYARSENAL_TAB_CARGOMAG) || (_tabIndex == IDC_RSCDISPLAYARSENAL_TAB_CARGOMAGALL);
    private _arrayMin = if (!isNil "jna_minItemMember" && {_tabIndex < count jna_minItemMember}) then { jna_minItemMember select _tabIndex } else { 0 };

    {
        _x params ["_item", "_count"];
        if (_item != "") then {
            if (_count == -1) then {
                // Unlimited / unlocked
                _availableItems set [_item, true];
            } else {
                if (_count > 0) then {
                    if (!_isMember && _enforceGuestLimits) then {
                        private _itemMin = if (!isNil "A3A_arsenalLimits") then { A3A_arsenalLimits getOrDefault [_item, [_arrayMin]] select 0 } else { _arrayMin };
                        if (_isMag) then {
                            private _magCount = getNumber (configFile >> "CfgMagazines" >> _item >> "count");
                            if (_magCount > 0) then { _itemMin = _itemMin * _magCount };
                        };
                        if ((_count - _itemMin) > 0) then {
                            _availableItems set [_item, true];
                        };
                    } else {
                        _availableItems set [_item, true];
                    };
                };
            };
        };
    } forEach _x;
} forEach jna_dataList;

// 2. Also include items currently equipped on the unit so player retains access to own gear
private _loadoutItemsHM = [getUnitLoadout _unit] call A3A_fnc_aceArsenalGetLoadoutItems;
{
    _availableItems set [_x, true];
} forEach (keys _loadoutItemsHM);

keys _availableItems;
