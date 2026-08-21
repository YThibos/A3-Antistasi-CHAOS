#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Draw event handler for the friendly zone-of-influence overlay ("borders").
    Attached to the vanilla M-map control by A3A_fnc_initMapOverlay and to the
    Y-menu commander / fast-travel / garrison map controls by fn_mainDialog and
    fn_hqDialog.  Fires once per frame per map control that renders.

    Draws two layers:
      - the border: the outline of friendly territory, as line segments.
      - the claim areas: each friendly zone's static-attribution footprint, in
        the marker's own shape, so what you see is what A3A_fnc_getMarkerForPos
        will actually claim.

    All geometry comes from the cache. The only work done here is the throttled
    staleness check in A3A_fnc_refreshInfluenceZones, which does a cheap
    signature comparison at most twice a second and only recomputes when the
    territory actually changed.

    Note: no visibleMap guard. visibleMap is only true for the vanilla map, so
    guarding on it would silently disable every dialog map, and a Draw EH does
    not fire unless its control is rendering anyway.

Arguments:
    0: <CONTROL> Map control, supplied by the Draw event handler

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_refreshInfluenceZones
    A3A_influenceBorder, A3A_influenceShapes  (set by A3A_fnc_computeInfluenceZones)
    A3A_CHAOS_influenceOverlayEnabled, A3A_CHAOS_influenceShowClaimAreas,
    A3A_CHAOS_influenceColour                 (CBA settings)
*/

params ["_map"];

// Read per-frame with a nil-safe default so toggling in Addon Options takes
// effect on the next frame without reopening the map.
if !(missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]) exitWith {};

[] call A3A_fnc_refreshInfluenceZones;

// ---- Colour -------------------------------------------------------------
// Index order matches the A3A_CHAOS_influenceColour LIST setting.
private _colIdx = missionNamespace getVariable ["A3A_CHAOS_influenceColour", 0];
private _rgb = [
    [0.1, 0.9, 0.3],   // 0  Green (default)
    [0,   0.9, 0.9],   // 1  Cyan
    [1,   0.9, 0.1],   // 2  Yellow
    [1,   1,   1  ],   // 3  White
    [0.2, 0.5, 1  ],   // 4  Blue
    [1,   0.5, 0  ],   // 5  Orange
    [0.8, 0.3, 1  ]    // 6  Purple
] param [_colIdx, [0.1, 0.9, 0.3]];

private _borderCol = _rgb + [0.9];
private _claimCol  = _rgb + [0.45];

// ---- Visible world rectangle, for culling -------------------------------
// Same idiom as fn_mapDrawOutpostsEH. On a fully zoomed-out late-game map the
// border can be a few thousand segments; culling keeps the usual zoomed-in
// case to the handful actually on screen.
private _mapPos   = ctrlMapPosition _map;
private _topLeft  = _map ctrlMapScreenToWorld [_mapPos # 0, _mapPos # 1];
private _botRight = _map ctrlMapScreenToWorld [(_mapPos # 0) + (_mapPos # 2), (_mapPos # 1) + (_mapPos # 3)];
private _viewMinX = (_topLeft # 0) min (_botRight # 0);
private _viewMaxX = (_topLeft # 0) max (_botRight # 0);
private _viewMinY = (_topLeft # 1) min (_botRight # 1);
private _viewMaxY = (_topLeft # 1) max (_botRight # 1);

// ---- Border -------------------------------------------------------------
{
    _x params ["_from", "_to"];
    private _ax = _from # 0;
    private _bx = _to # 0;
    private _ay = _from # 1;
    private _by = _to # 1;
    if ((_ax min _bx) <= _viewMaxX
        && {(_ax max _bx) >= _viewMinX}
        && {(_ay min _by) <= _viewMaxY}
        && {(_ay max _by) >= _viewMinY}) then {
        _map drawLine [_from, _to, _borderCol];
    };
} forEach (missionNamespace getVariable ["A3A_influenceBorder", []]);

// ---- Claim areas --------------------------------------------------------
if (missionNamespace getVariable ["A3A_CHAOS_influenceShowClaimAreas", true]) then {
    {
        _x params ["_pos", "_semiA", "_semiB", "_angle", "_isRect"];
        // Rotated shapes never reach further than their diagonal from the centre
        private _reach = sqrt ((_semiA * _semiA) + (_semiB * _semiB));
        if ((_pos # 0) - _reach <= _viewMaxX
            && {(_pos # 0) + _reach >= _viewMinX}
            && {(_pos # 1) - _reach <= _viewMaxY}
            && {(_pos # 1) + _reach >= _viewMinY}) then {
            if (_isRect) then {
                _map drawRectangle [_pos, _semiA, _semiB, _angle, _claimCol, ""];
            } else {
                _map drawEllipse [_pos, _semiA, _semiB, _angle, _claimCol, ""];
            };
        };
    } forEach (missionNamespace getVariable ["A3A_influenceShapes", []]);
};
