#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Extracts all item classnames and counts from getUnitLoadout format.

Scope: Any
Environment: Unscheduled
Public: Yes

Params:
    0: ARRAY - Loadout array from getUnitLoadout

Returns:
    HASHMAP - [className, count]
*/
params [["_loadout", [], [[]]]];

private _itemsHM = createHashMap;

private _fnc_addItem = {
    params ["_item", ["_amount", 1]];
    if (_item isEqualType "" && {_item != ""}) then {
        private _cfgWeap = configFile >> "CfgWeapons" >> _item;
        if (isClass _cfgWeap) then {
            _item = _item call BIS_fnc_baseWeapon;
            private _tfParent = getText (_cfgWeap >> "tf_parent");
            if (_tfParent != "") then { _item = _tfParent };
            private _acreBase = getText (configFile >> "CfgVehicles" >> _item >> "acre_baseClass");
            if (_acreBase != "") then { _item = _acreBase };
        };
        private _curr = _itemsHM getOrDefault [_item, 0];
        _itemsHM set [_item, _curr + _amount];
    };
};

if (_loadout isEqualTo []) exitWith { _itemsHM };

_loadout params [
    ["_primary", []],
    ["_secondary", []],
    ["_handgun", []],
    ["_uniform", []],
    ["_vest", []],
    ["_backpack", []],
    ["_headgear", ""],
    ["_goggles", ""],
    ["_binocular", []],
    ["_assigned", []]
];

// Weapons: [class, muzzle, pointer, optic, magPrimary [class, count], magSecondary [class, count], bipod]
{
    if (_x isEqualType [] && {!(_x isEqualTo [])}) then {
        _x params [
            ["_wClass", ""],
            ["_muzzle", ""],
            ["_pointer", ""],
            ["_optic", ""],
            ["_magPrimary", []],
            ["_magSecondary", []],
            ["_bipod", ""]
        ];
        [_wClass, 1] call _fnc_addItem;
        [_muzzle, 1] call _fnc_addItem;
        [_pointer, 1] call _fnc_addItem;
        [_optic, 1] call _fnc_addItem;
        [_bipod, 1] call _fnc_addItem;
        if (_magPrimary isEqualType [] && {!(_magPrimary isEqualTo [])}) then {
            [_magPrimary select 0, 1] call _fnc_addItem;
        };
        if (_magSecondary isEqualType [] && {!(_magSecondary isEqualTo [])}) then {
            [_magSecondary select 0, 1] call _fnc_addItem;
        };
    };
} forEach [_primary, _secondary, _handgun, _binocular];

// Containers: [class, [[item, count, (ammo)], ...]]
{
    if (_x isEqualType [] && {!(_x isEqualTo [])}) then {
        _x params [["_cClass", ""], ["_cItems", []]];
        [_cClass, 1] call _fnc_addItem;
        if (_cItems isEqualType []) then {
            {
                if (_x isEqualType []) then {
                    _x params [["_cItem", ""], ["_cCount", 1]];
                    if (_cItem isEqualType "") then {
                        [_cItem, _cCount] call _fnc_addItem;
                    };
                };
            } forEach _cItems;
        };
    };
} forEach [_uniform, _vest, _backpack];

// Headgear & Goggles
[_headgear, 1] call _fnc_addItem;
[_goggles, 1] call _fnc_addItem;

// Assigned items: [map, gps, radio, compass, watch, nvgs]
if (_assigned isEqualType []) then {
    {
        if (_x isEqualType "") then {
            [_x, 1] call _fnc_addItem;
        };
    } forEach _assigned;
};

_itemsHM;
