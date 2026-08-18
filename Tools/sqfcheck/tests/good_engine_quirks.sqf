// expect:
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_targets"];

// '#' is the select operator, not a preprocessor directive
private _first = _targets#0#1;
private _w = [];
{
    _w set [_forEachIndex, _x#0];
} forEach _targets;

// macro arguments carry raw paths with backslashes and dots
private _pic = QPATHTOFOLDER(Pictures\Intel\laptop_die.paa);
[] execVM QPATHTOFOLDER(Scripts\fn_advancedTowingInit.sqf);

#ifdef DEBUG_MODE_FULL
Info_1("first %1", _first);
#endif

private _s = 'single ''quoted'' string';
private _t = "double ""quoted"" string";
_first

// binary commands may continue the line after a code block
private _names = _targets apply { _x#0 } ;
private _map = keys _targets apply { "k_" + _x } createHashMapFromArray [];
private _i = 10;
waitUntil { _i = _i - 1; _i < 0 };

// deliberate assignment inside a code block nested in a condition
private _veh = objNull;
if (isNil { _veh = createVehicle ["C_Offroad_01_F", [0,0,0], [], 0, "NONE"]; nil }) then {
    Info_1("spawned %1", _veh);
};
