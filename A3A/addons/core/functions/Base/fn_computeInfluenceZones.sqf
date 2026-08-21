#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the cached client-side data for the friendly zone-of-influence map
    overlay ("borders").  Pure computation: it writes two globals and draws
    nothing.  A3A_GUI_fnc_mapDrawInfluenceEH consumes them.

      A3A_influenceShapes  - [[pos, semiA, semiB, angle, isRectangle], ...]
                             The static-attribution ("claim") area of every
                             teamPlayer-owned capturable zone, in the marker's
                             own shape so it matches the inArea test used by
                             A3A_fnc_getMarkerForPos.
      A3A_influenceBorder  - [[posA, posB], ...] world-space line segments that
                             together form the outline(s) of friendly territory.

    ---- How the border is produced ----------------------------------------
    A scalar influence field is sampled on a regular grid and its zero contour
    is extracted with marching squares.

      friendly(node) = max over friendly zones of (R - distance)
      enemy(node)    = max over enemy zones of (Re - distance), clamped at >= 0
      field(node)    = friendly(node) - enemy(node)
      border         = the field == 0 contour

    R = (largest marker semi-axis) max (linkDistance * 0.55), so two friendly
    zones closer together than the configured link distance always merge into
    one blob, and a lone zone still shows a sensible bubble.  Enemy zones carve
    the field back, so an enemy town or camp inside friendly territory punches
    a hole in the border instead of being silently enclosed.

    Marching squares was chosen over a hull or a union-of-discs construction
    because it needs no geometric predicates: disjoint territory yields several
    separate outlines, enclosed enemies yield inner outlines, and 0/1/2 zones,
    collinear zones, duplicated positions and zones on different landmasses all
    run through the same code path with no special cases.

    Cost is bounded, not capped: the grid cell size grows until both the node
    count and the rasterisation work fit a fixed budget, so a late-game map with
    hundreds of owned zones degrades to a coarser outline instead of switching
    the feature off.

Arguments:
    None

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    markersX, outpostsFIA, controlsX, sidesX, teamPlayer   (public globals)
    A3A_CHAOS_influenceLinkDist                            (CBA setting, default 2000)
    A3A_fnc_garrisonVehicleRadius
*/

if (isNil "markersX" || {isNil "outpostsFIA"} || {isNil "sidesX"}) exitWith {
    Debug("computeInfluenceZones: zone globals not ready yet - skipping");
    A3A_influenceShapes = [];
    A3A_influenceBorder = [];
};

// ---- 0. Tunables --------------------------------------------------------
private _cellMin     = 60;        // metres, finest grid resolution
private _gridSpanMax = 180;       // target grid nodes along the longest axis
private _nodeBudget  = 40000;     // ceiling on total grid nodes
private _stampBudget = 90000;     // ceiling on node writes during rasterisation
private _outside     = -1e7;      // field value for nodes no friendly zone reaches

// ---- 1. Configured link distance ----------------------------------------
private _linkDist = missionNamespace getVariable ["A3A_CHAOS_influenceLinkDist", 2000];
if !(_linkDist isEqualType 0) then { _linkDist = 2000 };
_linkDist = ((round (_linkDist / 100)) * 100) max 1000 min 5000;

// ---- 2. Collect friendly claim shapes, friendly discs and enemy discs ----
private _controls = missionNamespace getVariable ["controlsX", []];
private _wpRadius = [] call A3A_fnc_garrisonVehicleRadius;   // fixed watchpost/roadblock claim radius
private _halo     = _linkDist * 0.55;                        // guarantees overlap at exactly _linkDist

private _allZones = markersX + outpostsFIA + _controls;
private _postFrom = count markersX;
private _postTo   = _postFrom + count outpostsFIA;

private _shapes   = [];     // friendly claim areas, drawn as-is
private _friendly = [];     // [x, y, influenceRadius]
private _enemy    = [];     // [x, y, pushBackRadius]

{
    private _mrk = _x;
    private _pos = getMarkerPos _mrk;
    // Markers that were never broadcast to this client report [0,0,0]
    if (_pos isEqualTo [0,0,0]) then { continue };

    private _side = sidesX getVariable [_mrk, sideUnknown];
    if (_side isEqualTo sideUnknown) then { continue };

    private _semiA  = 0;
    private _semiB  = 0;
    private _isRect = false;
    if (_forEachIndex >= _postFrom && {_forEachIndex < _postTo}) then {
        // Watchposts / roadblocks: fixed circular claim radius, marker size is cosmetic
        _semiA = _wpRadius;
        _semiB = _wpRadius;
    } else {
        private _size = markerSize _mrk;
        _semiA = _size # 0;
        _semiB = _size # 1;
        _isRect = (markerShape _mrk) isEqualTo "RECTANGLE";
    };
    if (_semiA <= 0 || {_semiB <= 0}) then { continue };

    private _reach = _semiA max _semiB;
    if (_side isEqualTo teamPlayer) then {
        _shapes pushBack [_pos, _semiA, _semiB, markerDir _mrk, _isRect];
        _friendly pushBack [_pos # 0, _pos # 1, _reach max _halo];
    } else {
        _enemy pushBack [_pos # 0, _pos # 1, (_reach * 1.5) max 250];
    };
} forEach _allZones;

A3A_influenceShapes = _shapes;

if (_friendly isEqualTo []) exitWith {
    A3A_influenceBorder = [];
    Debug("computeInfluenceZones: no friendly zones - border cleared");
};

// ---- 3. Grid geometry ---------------------------------------------------
private _minX =  1e9;
private _maxX = -1e9;
private _minY =  1e9;
private _maxY = -1e9;
{
    _x params ["_px", "_py", "_r"];
    if (_px - _r < _minX) then { _minX = _px - _r };
    if (_px + _r > _maxX) then { _maxX = _px + _r };
    if (_py - _r < _minY) then { _minY = _py - _r };
    if (_py + _r > _maxY) then { _maxY = _py + _r };
} forEach _friendly;

private _spanX = _maxX - _minX;
private _spanY = _maxY - _minY;
private _cell  = ((_spanX max _spanY) / _gridSpanMax) max _cellMin;

// Grow the cell until both budgets are met. Bounded loop, never infinite.
private _fits  = false;
private _tries = 0;
while { !_fits && {_tries < 20} } do {
    _tries = _tries + 1;
    private _nodes  = ((floor (_spanX / _cell)) + 4) * ((floor (_spanY / _cell)) + 4);
    private _stamps = 0;
    {
        private _stampSpan = (2 * ((_x # 2) + 1.5 * _cell) / _cell) + 2;
        _stamps = _stamps + _stampSpan * _stampSpan;
    } forEach _friendly;
    if (_nodes <= _nodeBudget && {_stamps <= _stampBudget}) then { _fits = true } else { _cell = _cell * 1.3 };
};

private _ox = _minX - _cell;
private _oy = _minY - _cell;
private _nx = (floor (_spanX / _cell)) + 4;
private _ny = (floor (_spanY / _cell)) + 4;
private _nodeCount = _nx * _ny;

// ---- 4. Rasterise the influence field -----------------------------------
// Doubling fill: far cheaper than one pushBack per node on a 40k array.
private _field = [_outside];
while { count _field < _nodeCount } do { _field append (+_field) };
_field resize _nodeCount;

private _push = [0];
while { count _push < _nodeCount } do { _push append (+_push) };
_push resize _nodeCount;
private _pushed = [];

// Friendly: stamp (R - distance) out to 1.5 cells past R, so every positive
// node is surrounded by real (negative) samples and the contour can always
// interpolate instead of snapping to a node.
{
    _x params ["_px", "_py", "_r"];
    private _cover  = _r + 1.5 * _cell;
    private _cover2 = _cover * _cover;
    private _i0 = ((floor ((_px - _cover - _ox) / _cell)) max 0);
    private _i1 = ((ceil  ((_px + _cover - _ox) / _cell)) min (_nx - 1));
    private _j0 = ((floor ((_py - _cover - _oy) / _cell)) max 0);
    private _j1 = ((ceil  ((_py + _cover - _oy) / _cell)) min (_ny - 1));
    for "_j" from _j0 to _j1 do {
        private _dy   = (_oy + _j * _cell) - _py;
        private _base = _j * _nx;
        for "_i" from _i0 to _i1 do {
            private _dx = (_ox + _i * _cell) - _px;
            private _d2 = _dx * _dx + _dy * _dy;
            if (_d2 <= _cover2) then {
                private _idx = _base + _i;
                private _val = _r - sqrt _d2;
                if (_val > (_field select _idx)) then { _field set [_idx, _val] };
            };
        };
    };
} forEach _friendly;

// Enemy: stamp (Re - distance) where positive, tracking touched nodes so the
// subtraction below is applied exactly once per node.
{
    _x params ["_px", "_py", "_r"];
    private _r2 = _r * _r;
    private _i0 = ((floor ((_px - _r - _ox) / _cell)) max 0);
    private _i1 = ((ceil  ((_px + _r - _ox) / _cell)) min (_nx - 1));
    private _j0 = ((floor ((_py - _r - _oy) / _cell)) max 0);
    private _j1 = ((ceil  ((_py + _r - _oy) / _cell)) min (_ny - 1));
    for "_j" from _j0 to _j1 do {
        private _dy   = (_oy + _j * _cell) - _py;
        private _base = _j * _nx;
        for "_i" from _i0 to _i1 do {
            private _dx = (_ox + _i * _cell) - _px;
            private _d2 = _dx * _dx + _dy * _dy;
            if (_d2 < _r2) then {
                private _idx = _base + _i;
                private _val = _r - sqrt _d2;
                private _old = _push select _idx;
                if (_old <= 0) then { _pushed pushBack _idx };
                if (_val > _old) then { _push set [_idx, _val] };
            };
        };
    };
} forEach _enemy;

{ _field set [_x, (_field select _x) - (_push select _x)] } forEach _pushed;

// ---- 5. Marching squares over the zero contour --------------------------
// Corner layout per cell: 00 = bottom-left, 10 = bottom-right,
// 11 = top-right, 01 = top-left. Edges are bottom, right, top, left.
private _segments = [];
private _iLast = _nx - 2;
private _jLast = _ny - 2;

for "_j" from 0 to _jLast do {
    private _b0 = _j * _nx;
    private _b1 = _b0 + _nx;
    private _y0 = _oy + _j * _cell;
    private _y1 = _y0 + _cell;
    for "_i" from 0 to _iLast do {
        private _v00 = _field select (_b0 + _i);
        private _v10 = _field select (_b0 + _i + 1);
        private _v11 = _field select (_b1 + _i + 1);
        private _v01 = _field select (_b1 + _i);
        private _s00 = _v00 > 0;
        private _s10 = _v10 > 0;
        private _s11 = _v11 > 0;
        private _s01 = _v01 > 0;
        // Whole cell on one side of the contour: nothing to draw here.
        if (_s00 isEqualTo _s10 && {_s00 isEqualTo _s11} && {_s00 isEqualTo _s01}) then { continue };

        private _x0 = _ox + _i * _cell;
        private _x1 = _x0 + _cell;
        private _crossings = [];
        private _edgeB = [];
        private _edgeR = [];
        private _edgeT = [];
        private _edgeL = [];

        if !(_s00 isEqualTo _s10) then {
            _edgeB = [_x0 + _cell * (_v00 / (_v00 - _v10)), _y0, 0];
            _crossings pushBack _edgeB;
        };
        if !(_s10 isEqualTo _s11) then {
            _edgeR = [_x1, _y0 + _cell * (_v10 / (_v10 - _v11)), 0];
            _crossings pushBack _edgeR;
        };
        if !(_s01 isEqualTo _s11) then {
            _edgeT = [_x0 + _cell * (_v01 / (_v01 - _v11)), _y1, 0];
            _crossings pushBack _edgeT;
        };
        if !(_s00 isEqualTo _s01) then {
            _edgeL = [_x0, _y0 + _cell * (_v00 / (_v00 - _v01)), 0];
            _crossings pushBack _edgeL;
        };

        if (count _crossings == 2) then {
            _segments pushBack [_crossings # 0, _crossings # 1];
        } else {
            if (count _crossings == 4) then {
                // Saddle. Resolve with the cell average so the majority side stays connected.
                private _avg = (_v00 + _v10 + _v11 + _v01) / 4;
                if (_s00 isEqualTo (_avg > 0)) then {
                    _segments pushBack [_edgeB, _edgeR];
                    _segments pushBack [_edgeT, _edgeL];
                } else {
                    _segments pushBack [_edgeL, _edgeB];
                    _segments pushBack [_edgeR, _edgeT];
                };
            };
        };
    };
};

A3A_influenceBorder = _segments;
A3A_influenceCellSize = _cell;
Debug_5("computeInfluenceZones: link=%1m cell=%2m grid=%3x%4 segments=%5", _linkDist, round _cell, _nx, _ny, count _segments);
