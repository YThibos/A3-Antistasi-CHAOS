#include "..\..\script_component.hpp"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Handles closing of ACE Arsenal display. Computes inventory diff and enforces stocks.

Scope: Client
Environment: Scheduled
Public: No
*/
if (!hasInterface) exitWith {};
if (isNil "A3A_aceArsenal_isOpen" || {!A3A_aceArsenal_isOpen}) exitWith {};
A3A_aceArsenal_isOpen = false;

private _initialLoadout = missionNamespace getVariable ["A3A_aceArsenal_initialLoadout", []];
A3A_aceArsenal_initialLoadout = nil;
A3A_aceArsenal_activeBox = nil;

if (_initialLoadout isEqualTo []) exitWith {
    [clientOwner] remoteExecCall ["jn_fnc_arsenal_requestClose", 2];
};

private _currentLoadout = getUnitLoadout player;

// Calculate diff
([_initialLoadout, _currentLoadout] call A3A_fnc_aceArsenalDiffLoadout) params ["_itemsReturnedToBox", "_itemsTakenFromBox"];

// 1. Process items returned by player -> add back to arsenal
{
    _x params ["_item", "_count"];
    if (_count > 0 && _item != "") then {
        private _tab = _item call jn_fnc_arsenal_itemType;
        if (_tab != -1) then {
            [_tab, _item, _count] call jn_fnc_arsenal_addItem;
        };
    };
} forEach _itemsReturnedToBox;

// 2. Process items taken by player -> deduct from arsenal & enforce limits
private _isMember = [player] call A3A_fnc_isMember;
private _enforceGuestLimits = missionNamespace getVariable ["chaos_arsenal_enforceGuestLimits", true];
private _excessItems = [];
private _outOfStockItems = [];

{
    _x params ["_item", "_count"];
    if (_count > 0 && _item != "") then {
        private _tab = _item call jn_fnc_arsenal_itemType;
        if (_tab == -1) then {
            _outOfStockItems pushBack [_item, _count];
        } else {
            private _stock = [jna_dataList select _tab, _item] call jn_fnc_arsenal_itemCount;
            if (_stock == -1) then {
                // Unlimited, allowed
            } else {
                private _guestLimit = 0;
                if (!_isMember && _enforceGuestLimits) then {
                    private _arrayMin = if (!isNil "jna_minItemMember" && {_tab < count jna_minItemMember}) then { jna_minItemMember select _tab } else { 0 };
                    _guestLimit = if (!isNil "A3A_arsenalLimits") then { A3A_arsenalLimits getOrDefault [_item, [_arrayMin]] select 0 } else { _arrayMin };
                    if (_tab == IDC_RSCDISPLAYARSENAL_TAB_CARGOMAG || _tab == IDC_RSCDISPLAYARSENAL_TAB_CARGOMAGALL) then {
                        private _magCount = getNumber (configFile >> "CfgMagazines" >> _item >> "count");
                        if (_magCount > 0) then { _guestLimit = _guestLimit * _magCount };
                    };
                };
                private _availableStock = (_stock - _guestLimit) max 0;
                if (_availableStock <= 0) then {
                    _outOfStockItems pushBack [_item, _count];
                } else {
                    if (_count <= _availableStock) then {
                        [_tab, _item, _count] call jn_fnc_arsenal_removeItem;
                    } else {
                        private _excess = _count - _availableStock;
                        [_tab, _item, _availableStock] call jn_fnc_arsenal_removeItem;
                        _excessItems pushBack [_item, _excess];
                    };
                };
            };
        };
    };
} forEach _itemsTakenFromBox;

// If any excess or out-of-stock items exist, remove them from player's inventory and notify
if !(_outOfStockItems isEqualTo [] && _excessItems isEqualTo []) then {
    private _itemsToRemove = +_outOfStockItems;
    {
        _x params ["_item", "_excess"];
        _itemsToRemove pushBack [_item, _excess];
    } forEach _excessItems;

    [_itemsToRemove] call A3A_fnc_aceArsenalRemovePlayerItems;

    private _msg = "";
    if !(_outOfStockItems isEqualTo []) then {
        private _names = (_outOfStockItems apply {
            private _cfg = (_x select 0) call CBA_fnc_getItemConfig;
            format ["%1x %2", _x select 1, getText (_cfg >> "displayName")]
        }) joinString ", ";
        _msg = _msg + format ["<t color='#ff4444'>Restricted / Out of stock:</t><br/>%1<br/><br/>", _names];
    };
    if !(_excessItems isEqualTo []) then {
        private _names = (_excessItems apply {
            private _cfg = (_x select 0) call CBA_fnc_getItemConfig;
            format ["%1x %2", _x select 1, getText (_cfg >> "displayName")]
        }) joinString ", ";
        _msg = _msg + format ["<t color='#ffaa44'>Excess quantity removed:</t><br/>%1<br/>", _names];
    };

    [localize "STR_A3A_feedback_serverinfo", _msg] call A3A_fnc_customHint;
};

// Notify server that client has finished arsenal session
[clientOwner] remoteExecCall ["jn_fnc_arsenal_requestClose", 2];
