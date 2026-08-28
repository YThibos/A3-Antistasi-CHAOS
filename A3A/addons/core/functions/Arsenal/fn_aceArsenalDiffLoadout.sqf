#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Compares two unit loadouts and calculates the delta of returned and taken items.

Scope: Any
Environment: Unscheduled
Public: Yes

Params:
    0: ARRAY - Initial loadout (from getUnitLoadout)
    1: ARRAY - Current loadout (from getUnitLoadout)

Returns:
    ARRAY - [_itemsReturnedToBox, _itemsTakenFromBox]
        where each is an array of [className, count]
*/
params [["_initialLoadout", [], [[]]], ["_currentLoadout", [], [[]]]];

private _initialHM = [_initialLoadout] call A3A_fnc_aceArsenalGetLoadoutItems;
private _currentHM = [_currentLoadout] call A3A_fnc_aceArsenalGetLoadoutItems;

private _itemsReturnedToBox = [];
private _itemsTakenFromBox = [];

// Items removed from player loadout (returned to arsenal box)
{
    private _item = _x;
    private _oldCount = _y;
    private _newCount = _currentHM getOrDefault [_item, 0];
    if (_newCount < _oldCount) then {
        _itemsReturnedToBox pushBack [_item, _oldCount - _newCount];
    };
} forEach _initialHM;

// Items added to player loadout (taken from arsenal box)
{
    private _item = _x;
    private _newCount = _y;
    private _oldCount = _initialHM getOrDefault [_item, 0];
    if (_newCount > _oldCount) then {
        _itemsTakenFromBox pushBack [_item, _newCount - _oldCount];
    };
} forEach _currentHM;

[_itemsReturnedToBox, _itemsTakenFromBox];
