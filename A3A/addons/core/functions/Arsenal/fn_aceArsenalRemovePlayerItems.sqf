#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Safely removes excess or disallowed items from the player unit.

Scope: Client (local unit)
Environment: Unscheduled
Public: No

Params:
    0: ARRAY - Array of [_className, _countToRemove]
*/
params [["_itemsToRemove", [], [[]]]];

{
    _x params [["_item", "", [""]], ["_count", 0, [0]]];
    if (_item != "" && _count > 0) then {
        private _rem = _count;
        while {_rem > 0} do {
            private _removed = false;
            // Uniform
            if (_item in uniformItems player) exitWith {
                player removeItemFromUniform _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Vest
            if (_item in vestItems player) exitWith {
                player removeItemFromVest _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Backpack
            if (_item in backpackItems player) exitWith {
                player removeItemFromBackpack _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Assigned items
            if (_item in assignedItems player) exitWith {
                player unlinkItem _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Headgear / Goggles
            if (headgear player == _item) exitWith {
                removeHeadgear player;
                _rem = _rem - 1;
                _removed = true;
            };
            if (goggles player == _item) exitWith {
                removeGoggles player;
                _rem = _rem - 1;
                _removed = true;
            };
            // Weapons
            if (primaryWeapon player == _item) exitWith {
                player removeWeapon _item;
                _rem = _rem - 1;
                _removed = true;
            };
            if (secondaryWeapon player == _item) exitWith {
                player removeWeapon _item;
                _rem = _rem - 1;
                _removed = true;
            };
            if (handgunWeapon player == _item) exitWith {
                player removeWeapon _item;
                _rem = _rem - 1;
                _removed = true;
            };
            if (binocular player == _item) exitWith {
                player removeWeapon _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Weapon attachments
            if (_item in primaryWeaponItems player) exitWith {
                player removePrimaryWeaponItem _item;
                _rem = _rem - 1;
                _removed = true;
            };
            if (_item in secondaryWeaponItems player) exitWith {
                player removeSecondaryWeaponItem _item;
                _rem = _rem - 1;
                _removed = true;
            };
            if (_item in handgunItems player) exitWith {
                player removeHandgunItem _item;
                _rem = _rem - 1;
                _removed = true;
            };
            // Containers
            if (uniform player == _item) exitWith {
                removeUniform player;
                _rem = _rem - 1;
                _removed = true;
            };
            if (vest player == _item) exitWith {
                removeVest player;
                _rem = _rem - 1;
                _removed = true;
            };
            if (backpack player == _item) exitWith {
                removeBackpack player;
                _rem = _rem - 1;
                _removed = true;
            };
            // If not found anywhere else, exit
            if (!_removed) exitWith {};
        };
    };
} forEach _itemsToRemove;
