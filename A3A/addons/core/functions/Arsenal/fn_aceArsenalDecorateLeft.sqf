#include "..\..\script_component.hpp"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Decorates ACE Arsenal left panel items with stock quantities and weapon ammo indicators.

Scope: Client
Environment: Unscheduled
Public: No

Params:
    0: DISPLAY - Arsenal display
    1: NUMBER - Left tab IDC
*/
params ["_display", "_ctrlIDC"];

if (isNull _display) exitWith {};
if (isNil "A3A_aceArsenal_stockMap") exitWith {};

// Left content control is IDC 13 (IDC_leftTabContent)
private _ctrlList = _display displayCtrl 13;
if (isNull _ctrlList) exitWith {};

private _size = lbSize _ctrlList;
if (_size == 0) exitWith {};

// Weapon tabs check (Primary: 2002, Handgun: 2004, Secondary: 2006)
private _isWeaponTab = _ctrlIDC in [2002, 2004, 2006];
private _ammoLogo = "\A3\Ui_f\data\GUI\Rsc\RscDisplayArsenal\cargomag_ca.paa";

for "_i" from 0 to (_size - 1) do {
    private _item = _ctrlList lbData _i;

    if (_item != "") then {
        // 1. Stock quantity prefix
        private _stock = A3A_aceArsenal_stockMap getOrDefault [toLowerANSI _item, 0];
        private _stockStr = [_stock] call A3A_fnc_aceArsenalFormatStock;

        private _text = _ctrlList lbText _i;
        // Strip any existing prefix if already present
        if ((_text select [0, 2]) == "[ ") then {
            private _closeIdx = _text find " ] ";
            if (_closeIdx != -1) then {
                _text = _text select [_closeIdx + 3];
            };
        };
        _ctrlList lbSetText [_i, _stockStr + _text];

        // 2. Weapon ammo indicator (for primary, secondary, and handgun weapons)
        if (_isWeaponTab) then {
            private _compatableMags = compatibleMagazines _item;
            private _ammoTotal = 0;
            private _isUnlimited = false;

            {
                private _magStock = (missionNamespace getVariable ["A3A_aceArsenal_magMap", createHashMap]) getOrDefault [toLowerANSI _x, 0];
                if (_magStock == -1) exitWith { _isUnlimited = true; };
                _ammoTotal = _ammoTotal + _magStock;
            } forEach _compatableMags;

            if (_isUnlimited) then { _ammoTotal = -1; };

            private _threshold = switch ((_item call BIS_fnc_itemType) select 1) do {
                case "AssaultRifle": { 1500 };
                case "Handgun": { 400 };
                case "MachineGun": { 4000 };
                case "Shotgun": { 300 };
                case "Rifle": { 1500 };
                case "SubmachineGun": { 800 };
                case "SniperRifle": { 200 };
                default { 20 }; // Launchers / missile systems
            };

            private _colorMult = if (_ammoTotal == -1) then { 1 } else { (_ammoTotal / _threshold) min 1 };
            private _red = -0.6 * _colorMult + 0.8;
            private _green = 0.6 * _colorMult + 0.2;
            private _ammoColor = [_red, _green, 0.3, 1];

            _ctrlList lbSetPictureRight [_i, _ammoLogo];
            _ctrlList lbSetPictureRightColor [_i, _ammoColor];
            _ctrlList lbSetPictureRightColorSelected [_i, _ammoColor];
        };
    };
};
