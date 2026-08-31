#include "..\..\script_component.hpp"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Decorates ACE Arsenal right panel items with stock quantities.

Scope: Client
Environment: Unscheduled
Public: No

Params:
    0: DISPLAY - Arsenal display
    1: NUMBER - Right tab IDC
*/
params ["_display", "_ctrlIDC"];

if (isNull _display) exitWith {};
if (isNil "A3A_aceArsenal_stockMap") exitWith {};

// Right panel can be ListBox (IDC 14) for weapon attachments, or ListNBox (IDC 15) for cargo items
private _ctrlListBox = _display displayCtrl 14;
private _ctrlListNBox = _display displayCtrl 15;

// If ListNBox is active (cargo container items)
if (!isNull _ctrlListNBox && {ctrlShown _ctrlListNBox}) then {
    private _rowCount = (lnbSize _ctrlListNBox) select 0;
    for "_i" from 0 to (_rowCount - 1) do {
        private _item = _ctrlListNBox lnbData [_i, 0];
        if (_item != "") then {
            private _stock = A3A_aceArsenal_stockMap getOrDefault [toLowerANSI _item, 0];
            private _stockStr = [_stock] call A3A_fnc_aceArsenalFormatStock;

            private _text = _ctrlListNBox lnbText [_i, 1];
            if ((_text select [0, 2]) == "[ ") then {
                private _closeIdx = _text find " ] ";
                if (_closeIdx != -1) then {
                    _text = _text select [_closeIdx + 3];
                };
            };
            _ctrlListNBox lnbSetText [[_i, 1], _stockStr + _text];
        };
    };
};

// If ListBox is active (weapon attachments: optics, muzzle, pointers, bipods)
if (!isNull _ctrlListBox && {ctrlShown _ctrlListBox}) then {
    private _size = lbSize _ctrlListBox;
    for "_i" from 0 to (_size - 1) do {
        private _item = _ctrlListBox lbData _i;
        if (_item != "") then {
            private _stock = A3A_aceArsenal_stockMap getOrDefault [toLowerANSI _item, 0];
            private _stockStr = [_stock] call A3A_fnc_aceArsenalFormatStock;

            private _text = _ctrlListBox lbText _i;
            if ((_text select [0, 2]) == "[ ") then {
                private _closeIdx = _text find " ] ";
                if (_closeIdx != -1) then {
                    _text = _text select [_closeIdx + 3];
                };
            };
            _ctrlListBox lbSetText [_i, _stockStr + _text];
        };
    };
};
