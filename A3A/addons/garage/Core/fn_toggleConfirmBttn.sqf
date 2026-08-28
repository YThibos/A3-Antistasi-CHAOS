/*
    Author: [Håkon]
    [Description]
        Toggles the buttons Confirm and [Un]Lock on/off

    Arguments:
    0. <Bool> Enable controls

    Return Value:
    <nil>

    Scope: Clients
    Environment: Any
    Public: [No]
    Dependencies:

    Example: [false] call HR_GRG_fnc_toggleConfirmBttn;

    License: APL-ND
*/
#include "defines.inc"
FIX_LINE_NUMBERS()
params ["_enable"];

private _disp = findDisplay HR_GRG_IDD_Garage;
private _ctrlCnfrm = _disp displayCtrl HR_GRG_IDC_Confirm;
private _ctrlLock = _disp displayCtrl HR_GRG_IDC_tLock;

_ctrlLock ctrlEnable _enable;

private _selVehicleCat = HR_GRG_SelectedVehicles#0;
private _fnc_enable = {
    _ctrlCnfrm ctrlEnable _enable;
    _ctrlCnfrm ctrlSetTextColor [1,1,1,1];
    _ctrlCnfrm ctrlSetTooltip "";
};
private _fnc_disable = {
    _ctrlCnfrm ctrlEnable false;
    _ctrlCnfrm ctrlSetTextColor [0.7,0,0,1];
    _ctrlCnfrm ctrlSetTooltip _this;
};

if (HR_GRG_accessLimit == "helipad") exitWith {
    if (_selVehicleCat in HR_GRG_HELIPADACCESSIBLE) then {
        call _fnc_enable;
    } else {
        (localize "STR_HR_GRG_Generic_HelipadDisabled") call _fnc_disable;
    };
};

if (call HR_GRG_Cnd_isAirbase) exitWith {
    call _fnc_enable;
};

private _accessObj = if (!isNull HR_GRG_accessPoint) then { HR_GRG_accessPoint } else { player };
private _hqRadius = call A3A_fnc_hqBuildRadius;
private _isAtHQ = (_accessObj inArea "Synd_HQ") || { (_accessObj distance2D (getMarkerPos "Synd_HQ")) <= _hqRadius };

if (_selVehicleCat in HR_GRG_HELIPADACCESSIBLE) exitWith {
    private _hasNearbyHelipad = (count (nearestObjects [_accessObj, ["a3a_helipad", "Helipad_Base_F"], 50, true]) > 0)
        || (_isAtHQ && { count (nearestObjects [getMarkerPos "Synd_HQ", ["a3a_helipad", "Helipad_Base_F"], _hqRadius, true]) > 0 });

    if (_hasNearbyHelipad) then {
        call _fnc_enable;
    } else {
        (localize "STR_HR_GRG_Generic_HelipadDisabled") call _fnc_disable;
    };
};

if (_selVehicleCat == 4) exitWith {
    if (_isAtHQ && {call A3A_fnc_hasAirControlCenter}) then {
        call _fnc_enable;
    } else {
        (localize "STR_HR_GRG_Generic_AirDisabled") call _fnc_disable;
    };
};

call _fnc_enable;
