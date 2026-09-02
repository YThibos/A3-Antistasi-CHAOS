#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Evaluates the influence field at one point and returns who holds it.

    This is the gather form of exactly the model fn_computeInfluenceZones
    rasterises by scattering. Same cones, same weights, same saturation, same
    strictly-highest-wins rule - so the supply graph and the drawn border
    cannot disagree about who owns a piece of ground.

        contribution(zone, p) = max(0, 1 - d/R)  +  W * max(0, 1 - d/(M*R))
        influence(side, p)    = saturate( sum of that side's contributions )
        saturate(v)           = v                      for v <= cap
                              = cap + tail*(1 - cap/v) for v > cap

    ---- Keep this in step with the rasteriser ------------------------------
    The two forms are written out separately on purpose: the rasteriser walks a
    bounded box per zone and writes into a flat field array, which is the only
    way it can afford 36 000 nodes, while this walks the zones near one point.
    A shared per-point helper would be a function call per grid node and would
    cost the overlay far more than the duplication costs us. Every constant
    they share comes from A3A_fnc_influenceContext, so only these four lines of
    arithmetic are duplicated - if you change the cone or the saturation in one
    place, change it in the other. Section 5 and 6 of fn_computeInfluenceZones
    are the counterparts.

    The rasteriser additionally floors each radius at 1.5 grid cells so a tiny
    zone cannot fall between sample points. That floor belongs to the grid, not
    to the field, and is deliberately absent here - see fn_influenceContext.

Arguments:
    0: <ARRAY>  Context from A3A_fnc_influenceContext.
    1: <ARRAY>  Position: [x, y] or [x, y, z]; z is ignored.

Return Value:
    <ARRAY> [_ownerIdx, _advantage]
        _ownerIdx  <NUMBER> index into the context's _sideList, or -1 when no
                            side reaches the point or two sides tie exactly.
        _advantage <NUMBER> the owner's influence minus the best rival's, 0
                            when _ownerIdx is -1.

Scope: Anywhere
Environment: Unscheduled
Public: No
*/

params [
    ["_ctx", [], [[]]],
    ["_pos", [0,0], [[]]]
];

if (_ctx isEqualTo []) exitWith { [-1, 0] };

_ctx params ["_sideList", "", "_consts", "_buckets", "_bucketCell"];
_consts params ["_cap", "_capTail", "_tailW", "_reach"];

private _px = _pos param [0, 0, [0]];
private _py = _pos param [1, 0, [0]];

private _key = format ["%1,%2", floor (_px / _bucketCell), floor (_py / _bucketCell)];
private _near = _buckets getOrDefault [_key, []];
if (_near isEqualTo []) exitWith { [-1, 0] };

// ---- Sum each side's cones ----------------------------------------------
// resize would fill with nil, and a nil element poisons the arithmetic below,
// so the accumulator is built explicitly.
private _sums = [];
{ _sums pushBack 0 } forEach _sideList;

{
    _x params ["_sideIdx", "_zx", "_zy", "_r"];
    private _dx = _zx - _px;
    private _dy = _zy - _py;
    private _d = sqrt (_dx * _dx + _dy * _dy);

    private _v = 0;
    if (_d < _r) then { _v = 1 - _d / _r };
    if (_reach > 0) then {
        private _rt = _r * _reach;
        if (_d < _rt) then { _v = _v + _tailW * (1 - _d / _rt) };
    };
    if (_v > 0) then { _sums set [_sideIdx, (_sums select _sideIdx) + _v] };
} forEach _near;

// ---- Saturate, then strictly-highest-wins -------------------------------
private _best = 0;
private _second = 0;
private _bestIdx = -1;

{
    private _v = _x;
    if (_v > _cap) then { _v = _cap + _capTail * (1 - _cap / _v) };
    if (_v > _best) then {
        _second = _best;
        _best = _v;
        _bestIdx = _forEachIndex;
    } else {
        if (_v > _second) then { _second = _v };
    };
} forEach _sums;

if (_best <= 0) exitWith { [-1, 0] };
if (_best <= _second) exitWith { [-1, 0] };

[_bestIdx, _best - _second]
