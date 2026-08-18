// expect:
params [["_unit", objNull, [objNull]]];
private _n = 0;
if (alive _unit) then {
    _n = 1;
} else {
    _n = 2;
};
for "_i" from 0 to 3 do {
    private _s = format ["%1 ""quoted"" %2", _i, _n];
    diag_log _s;
};
switch (_n) do {
    case 1: { _n = 10 };
    case 2;
    default { _n = 0 };
};
private _r = [_unit, _n] call A3A_fnc_someThing;
_r
