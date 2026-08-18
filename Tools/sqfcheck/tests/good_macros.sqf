// expect: 
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_side", ["_count", 1]];

private _units = [];
{
    if (alive _x) then { _units pushBack _x };
} forEach (units group player);

private _n = {alive _x} count _units;
Info_1("Found %1 units", _n);
if (_n isEqualTo 0) exitWith { false };
private _map = createHashMapFromArray [["a", 1], ["b", 2]];
private _v = _map getOrDefault ["a", 0];
_units apply { _x setVariable [QGVAR(tagged), true, true] };
true
