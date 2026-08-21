#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the cached client-side data for the zone-of-influence map overlay
    ("borders"). Pure computation: it writes globals and draws nothing.
    A3A_GUI_fnc_mapDrawInfluenceEH consumes them.

      A3A_influenceSides   - one entry per side that holds ground, in draw
                             order (enemies first, the player faction last):
                               [ [r,g,b],                       side colour
                                 [[posA, posB, nx, ny], ...],   border segments
                                 [pos, pos, pos, ...] ]         fill triangles
                             nx/ny is the segment's unit normal, precomputed so
                             the draw handler can offset copies for line width
                             without a square root per frame. The fill array is
                             a flat list of vertices in multiples of three, the
                             shape drawTriangle wants, and is empty unless the
                             fill setting is on.
      A3A_influenceShapes  - the static-attribution ("claim") area of every
                             teamPlayer-owned zone, in the marker's own shape,
                             so it matches the inArea test fn_getMarkerForPos
                             uses.
      A3A_influencePlayerColour - the player faction's [r,g,b], so the claim
                             area layer can be drawn without hunting through
                             A3A_influenceSides for the right entry.
      A3A_influenceCellSize - grid resolution actually used, for diagnostics.

    ---- The influence model -------------------------------------------------
    Every zone projects a cone of influence that is 1 at its centre and falls
    linearly to 0 at its own radius R:

        contribution(zone, p) = max(0, 1 - distance(zone, p) / R(zone))

    R comes from A3A_fnc_zoneInfluenceRadii, which scales the configured
    reference range ("Influence range") by a per-TYPE multiplier - identical
    for every side, so an enemy outpost pushes exactly as hard as a rebel one -
    and by a training factor derived from skillFIA.

    A side's influence at a point is the SUM of its zones' contributions, with
    a ceiling:

        influence(side, p) = saturate( sum of contributions )
        saturate(v) = v                       for v <= 1
                    = 1 + 0.05 * (1 - 1/v)    for v > 1

    The ceiling is what stops a cluster of small markers out-pushing a large
    zone: however many roadblocks are stacked on one spot, their combined
    influence can never exceed 1.05, while a single zone at its own centre is
    already 1.0. The 5% tail above the ceiling is deliberate - a hard clamp
    would make two saturated sides tie exactly over a whole region, which
    produces degenerate zero-length contour segments. With the tail the
    ordering stays strict everywhere.

    A node belongs to the side with the strictly highest influence there. Each
    side's border is the contour of

        advantage(side, p) = influence(side, p) - max over the other sides

    at zero, extracted with marching squares. Every side is computed on the
    SAME grid and the whole map is contoured in a single cell pass, because the
    owner of a node fixes the sign of the advantage for every side at once: a
    cell whose four corners share one owner cannot contain any side's border
    and is skipped after four array reads.

    Three sides are handled, not two, and a configuration with no Invaders (or
    any other side arrangement) needs no special case: sides are collected from
    the zones that actually exist, so a side holding no ground never appears.

    Marching squares was chosen over a hull or a union-of-discs construction
    because it needs no geometric predicates: disjoint territory yields several
    outlines, enclosed enemies yield inner outlines, and 0/1/2 zones, collinear
    zones, duplicated positions and separate landmasses all take the same path.

    Cost is bounded, not capped: the grid cell grows until the node count and
    the rasterisation work fit fixed budgets, so a late-game map degrades to a
    coarser outline instead of switching the feature off. Measured against an
    Altis-sized census, the three-side pass costs 0.86x-1.08x the old two-side
    one at the same resolution.

Arguments:
    None

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    markersX, outpostsFIA, controlsX, sidesX, teamPlayer, Occupants, Invaders,
    colorTeamPlayer, colorOccupants, colorInvaders, skillFIA  (public globals)
    A3A_CHAOS_influenceRange, A3A_CHAOS_influenceFill         (CBA settings)
    A3A_fnc_zoneInfluenceRadii, A3A_fnc_garrisonVehicleRadius
*/

if (isNil "markersX" || {isNil "outpostsFIA"} || {isNil "sidesX"}) exitWith {
    Debug("computeInfluenceZones: zone globals not ready yet - skipping");
    A3A_influenceSides = [];
    A3A_influenceShapes = [];
};

// ---- 0. Tunables --------------------------------------------------------
private _cellMin     = 60;         // metres, finest grid resolution
private _gridSpanMax = 180;        // target grid nodes along the longest axis
private _nodeBudget  = 36000;      // ceiling on total grid nodes
private _stampBudget = 80000;      // ceiling on node writes during rasterisation
private _empty       = -1e-4;      // advantage at nodes no side reaches. Small and
                                   // negative rather than zero so a contour can
                                   // never land exactly on a node, which would
                                   // collapse two crossings into one point.
private _cap         = 1;          // influence ceiling
private _capTail     = 0.05;       // residual slope above the ceiling
private _fillBudget  = 12000;      // max fill triangles per side

// ---- 1. Settings and scaling --------------------------------------------
private _refRange = missionNamespace getVariable ["A3A_CHAOS_influenceRange", 800];
if !(_refRange isEqualType 0) then { _refRange = 800 };
_refRange = ((round (_refRange / 100)) * 100) max 100 min 1400;

private _doFill = missionNamespace getVariable ["A3A_CHAOS_influenceFill", false];
if !(_doFill isEqualType false) then { _doFill = false };

// Rebel AI training, raised in HQ Management. fn_FIAskillAdd starts it at 1 and
// refuses past 20, and the HQ dialog shows it as "n / 20".
private _skill = missionNamespace getVariable ["skillFIA", 1];
if !(_skill isEqualType 0) then { _skill = 1 };
private _trainScale = 0.8 + 0.4 * (((_skill max 1) min 20) - 1) / 19;

private _radii = [_refRange, _trainScale] call A3A_fnc_zoneInfluenceRadii;
private _defaultRadius = _refRange * _trainScale;

// ---- 2. Collect zones per side and friendly claim shapes ----------------
private _controls = missionNamespace getVariable ["controlsX", []];
private _wpRadius = [] call A3A_fnc_garrisonVehicleRadius;   // watchpost/roadblock claim radius

private _allZones = markersX + outpostsFIA + _controls;
private _postFrom = count markersX;
private _postTo   = _postFrom + count outpostsFIA;

private _shapes    = [];     // friendly claim areas, drawn as-is
private _sideList  = [];     // SIDEs that hold ground
private _sideZones = [];     // parallel: [[x, y, radius], ...] per side

{
    private _mrk = _x;
    private _pos = getMarkerPos _mrk;
    // Markers that were never broadcast to this client report [0,0,0]
    if (_pos isEqualTo [0,0,0]) then { continue };

    private _side = sidesX getVariable [_mrk, sideUnknown];
    if (_side isEqualTo sideUnknown) then { continue };

    private _radius = _radii getOrDefault [_mrk, _defaultRadius];
    if (_radius <= 0) then { continue };

    private _idx = _sideList find _side;
    if (_idx < 0) then {
        _sideList pushBack _side;
        _sideZones pushBack [];
        _idx = (count _sideList) - 1;
    };
    (_sideZones select _idx) pushBack [_pos # 0, _pos # 1, _radius];

    if (_side isEqualTo teamPlayer) then {
        private _semiA = 0;
        private _semiB = 0;
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
        if (_semiA > 0 && {_semiB > 0}) then {
            _shapes pushBack [_pos, _semiA, _semiB, markerDir _mrk, _isRect];
        };
    };
} forEach _allZones;

A3A_influenceShapes = _shapes;

if (_sideList isEqualTo []) exitWith {
    A3A_influenceSides = [];
    Debug("computeInfluenceZones: no owned zones - overlay cleared");
};

// Draw order: the player faction last, so its border sits on top of the others.
private _playerIdx = _sideList find teamPlayer;
if (_playerIdx >= 0 && {_playerIdx != (count _sideList) - 1}) then {
    _sideList pushBack (_sideList deleteAt _playerIdx);
    _sideZones pushBack (_sideZones deleteAt _playerIdx);
};

// ---- 3. Side colours, from the game's own marker colour config ----------
// colorTeamPlayer / colorOccupants / colorInvaders hold CfgMarkerColors class
// names ("colorGUER", "colorBLUFOR", "colorOPFOR" by default), so the overlay
// matches whatever the faction actually uses on this map and in this config.
private _sideColours = [];
{
    private _side = _x;
    private _colourName = call {
        if (_side isEqualTo teamPlayer) exitWith { missionNamespace getVariable ["colorTeamPlayer", "colorGUER"] };
        if (!isNil "Occupants" && {_side isEqualTo Occupants}) exitWith { missionNamespace getVariable ["colorOccupants", "colorBLUFOR"] };
        if (!isNil "Invaders" && {_side isEqualTo Invaders}) exitWith { missionNamespace getVariable ["colorInvaders", "colorOPFOR"] };
        "colorUNKNOWN"
    };
    private _rgb = [0.45, 0.45, 0.45];
    private _cfg = getArray (configFile >> "CfgMarkerColors" >> _colourName >> "color");
    if (count _cfg >= 3
        && {(_cfg # 0) isEqualType 0}
        && {(_cfg # 1) isEqualType 0}
        && {(_cfg # 2) isEqualType 0}) then {
        _rgb = [_cfg # 0, _cfg # 1, _cfg # 2];
    };
    _sideColours pushBack _rgb;
} forEach _sideList;

private _playerColourIdx = _sideList find teamPlayer;
A3A_influencePlayerColour = if (_playerColourIdx < 0) then { [0, 0.5, 0] } else { _sideColours select _playerColourIdx };

// ---- 4. Grid geometry ---------------------------------------------------
private _minX =  1e9;
private _maxX = -1e9;
private _minY =  1e9;
private _maxY = -1e9;
{
    {
        _x params ["_px", "_py", "_r"];
        if (_px - _r < _minX) then { _minX = _px - _r };
        if (_px + _r > _maxX) then { _maxX = _px + _r };
        if (_py - _r < _minY) then { _minY = _py - _r };
        if (_py + _r > _maxY) then { _maxY = _py + _r };
    } forEach _x;
} forEach _sideZones;

private _spanX = _maxX - _minX;
private _spanY = _maxY - _minY;
private _cell  = ((_spanX max _spanY) / _gridSpanMax) max _cellMin;

// Grow the cell until both budgets are met. Bounded loop, never infinite.
private _fits  = false;
private _tries = 0;
while { !_fits && {_tries < 20} } do {
    _tries = _tries + 1;
    private _nodes  = ((floor (_spanX / _cell)) + 6) * ((floor (_spanY / _cell)) + 6);
    private _stamps = 0;
    {
        {
            private _stampSpan = (2 * (((_x # 2) max (1.5 * _cell)) + 1.5 * _cell) / _cell) + 2;
            _stamps = _stamps + _stampSpan * _stampSpan;
        } forEach _x;
    } forEach _sideZones;
    if (_nodes <= _nodeBudget && {_stamps <= _stampBudget}) then { _fits = true } else { _cell = _cell * 1.3 };
};

// Two cells of margin: the resolution floor below can grow a zone by up to
// 1.5 cells past the bounds these were measured from.
private _ox = _minX - 2 * _cell;
private _oy = _minY - 2 * _cell;
private _nx = (floor (_spanX / _cell)) + 6;
private _ny = (floor (_spanY / _cell)) + 6;
private _nodeCount = _nx * _ny;
private _radiusFloor = 1.5 * _cell;      // a zone smaller than the grid would vanish

// ---- 5. Rasterise one influence field per side --------------------------
// Doubling fill: far cheaper than one pushBack per node on a 36k array.
private _zeroRow = [0];
while { count _zeroRow < _nodeCount } do { _zeroRow append (+_zeroRow) };
_zeroRow resize _nodeCount;

private _fields = [];
{
    private _field = +_zeroRow;
    {
        _x params ["_px", "_py", "_r0"];
        private _r  = _r0 max _radiusFloor;
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
                    _field set [_idx, (_field select _idx) + 1 - (sqrt _d2) / _r];
                };
            };
        };
    } forEach _x;
    _fields pushBack _field;
} forEach _sideZones;

// ---- 6. Owner and per-side advantage, in one pass -----------------------
// owner = the side index that strictly holds the node, -1 if none.
// advantage[side] > 0 exactly when owner == side, by construction.
private _sideCount = count _sideList;
private _emptyRow = [_empty];
while { count _emptyRow < _nodeCount } do { _emptyRow append (+_emptyRow) };
_emptyRow resize _nodeCount;

private _owner = +_zeroRow;
private _diffs = [];
for "_s" from 0 to (_sideCount - 1) do { _diffs pushBack (+_emptyRow) };

private _vals = [];
_vals resize _sideCount;
private _sLast = _sideCount - 1;
for "_n" from 0 to (_nodeCount - 1) do {
    private _any = false;
    for "_s" from 0 to _sLast do {
        if (((_fields select _s) select _n) > 0) exitWith { _any = true };
    };
    if (!_any) then { _owner set [_n, -1]; continue };

    private _best = 0;
    private _second = 0;
    private _bestIdx = -1;
    for "_s" from 0 to _sLast do {
        private _v = (_fields select _s) select _n;
        if (_v > _cap) then { _v = _cap + _capTail * (1 - _cap / _v) };
        _vals set [_s, _v];
        if (_v > _best) then { _second = _best; _best = _v; _bestIdx = _s }
        else { if (_v > _second) then { _second = _v } };
    };
    if (_best <= _second) then { _bestIdx = -1 };
    _owner set [_n, _bestIdx];
    for "_s" from 0 to _sLast do {
        (_diffs select _s) set [_n, (_vals select _s) - ([_best, _second] select (_s isEqualTo _bestIdx))];
    };
};

// ---- 7. One marching-squares pass for every side ------------------------
// Corner layout per cell: 00 = bottom-left, 10 = bottom-right,
// 11 = top-right, 01 = top-left. Edges are bottom, right, top, left.
private _segs  = [];
private _fills = [];
for "_s" from 0 to _sLast do { _segs pushBack []; _fills pushBack [] };

private _jLast = _ny - 2;
private _iLast = _nx - 2;
private _xRight = _ox + (_nx - 1) * _cell;

for "_j" from 0 to _jLast do {
    private _b0 = _j * _nx;
    private _b1 = _b0 + _nx;
    private _y0 = _oy + _j * _cell;
    private _y1 = _y0 + _cell;
    private _runSide = -1;
    private _runX = 0;

    for "_i" from 0 to _iLast do {
        private _o00 = _owner select (_b0 + _i);
        private _o10 = _owner select (_b0 + _i + 1);
        private _o11 = _owner select (_b1 + _i + 1);
        private _o01 = _owner select (_b1 + _i);
        private _x0 = _ox + _i * _cell;

        if (_o00 isEqualTo _o10 && {_o00 isEqualTo _o11} && {_o00 isEqualTo _o01}) then {
            // Whole cell held by one side, or by nobody: no border here.
            if (_doFill && {_o00 >= 0} && {_runSide != _o00}) then {
                if (_runSide >= 0) then {
                    (_fills select _runSide) append [[_runX,_y0],[_x0,_y0],[_x0,_y1],[_runX,_y0],[_x0,_y1],[_runX,_y1]];
                };
                _runSide = _o00;
                _runX = _x0;
            };
            continue;
        };
        if (_doFill && {_runSide >= 0}) then {
            (_fills select _runSide) append [[_runX,_y0],[_x0,_y0],[_x0,_y1],[_runX,_y0],[_x0,_y1],[_runX,_y1]];
            _runSide = -1;
        };
        if (_o00 < 0 && {_o10 < 0} && {_o11 < 0} && {_o01 < 0}) then { continue };

        private _x1 = _x0 + _cell;
        private _p00 = [_x0,_y0];
        private _p10 = [_x1,_y0];
        private _p11 = [_x1,_y1];
        private _p01 = [_x0,_y1];

        private _todo = [];
        if (_o00 >= 0) then { _todo pushBackUnique _o00 };
        if (_o10 >= 0) then { _todo pushBackUnique _o10 };
        if (_o11 >= 0) then { _todo pushBackUnique _o11 };
        if (_o01 >= 0) then { _todo pushBackUnique _o01 };

        {
            private _k = _x;
            private _d = _diffs select _k;
            private _v00 = _d select (_b0 + _i);
            private _v10 = _d select (_b0 + _i + 1);
            private _v11 = _d select (_b1 + _i + 1);
            private _v01 = _d select (_b1 + _i);
            private _s00 = _o00 isEqualTo _k;
            private _s10 = _o10 isEqualTo _k;
            private _s11 = _o11 isEqualTo _k;
            private _s01 = _o01 isEqualTo _k;

            private _edgeB = [];
            private _edgeR = [];
            private _edgeT = [];
            private _edgeL = [];
            private _crossings = [];
            if !(_s00 isEqualTo _s10) then {
                _edgeB = [_x0 + _cell * (_v00 / (_v00 - _v10)), _y0];
                _crossings pushBack _edgeB;
            };
            if !(_s10 isEqualTo _s11) then {
                _edgeR = [_x1, _y0 + _cell * (_v10 / (_v10 - _v11))];
                _crossings pushBack _edgeR;
            };
            if !(_s01 isEqualTo _s11) then {
                _edgeT = [_x0 + _cell * (_v01 / (_v01 - _v11)), _y1];
                _crossings pushBack _edgeT;
            };
            if !(_s00 isEqualTo _s01) then {
                _edgeL = [_x0, _y0 + _cell * (_v00 / (_v00 - _v01))];
                _crossings pushBack _edgeL;
            };

            private _avg = (_v00 + _v10 + _v11 + _v01) / 4;
            private _segList = _segs select _k;
            // Zero-length segments happen when two sides tie exactly on a node.
            // They cannot be drawn and have no direction, so drop them.
            private _fnc_push = {
                params ["_a", "_b"];
                private _ddx = (_b # 0) - (_a # 0);
                private _ddy = (_b # 1) - (_a # 1);
                private _len = sqrt (_ddx * _ddx + _ddy * _ddy);
                if (_len > 1e-4) then { _segList pushBack [_a, _b, _ddy / _len, - _ddx / _len] };
            };

            if (count _crossings == 2) then {
                [_crossings # 0, _crossings # 1] call _fnc_push;
            } else {
                // Saddle. The positive region is connected exactly when the cell
                // average is positive; resolve both the contour and the fill from
                // that one test so the two cannot disagree.
                if (_s00 isEqualTo (_avg > 0)) then {
                    [_edgeB, _edgeR] call _fnc_push;
                    [_edgeT, _edgeL] call _fnc_push;
                } else {
                    [_edgeL, _edgeB] call _fnc_push;
                    [_edgeR, _edgeT] call _fnc_push;
                };
            };

            if (_doFill && {count (_fills select _k) < 3 * _fillBudget}) then {
                // The part of this cell that belongs to side _k, as a polygon,
                // fanned into triangles from its first vertex. Verified
                // exhaustively: this polygon plus the one for the complement
                // always add up to exactly one cell.
                private _cnt = ([0,1] select _s00) + ([0,1] select _s10) + ([0,1] select _s11) + ([0,1] select _s01);
                private _poly = [];
                switch (_cnt) do {
                    case 1: {
                        if (_s00) then { _poly = [_p00, _edgeB, _edgeL] }
                        else { if (_s10) then { _poly = [_p10, _edgeR, _edgeB] }
                        else { if (_s11) then { _poly = [_p11, _edgeT, _edgeR] }
                        else { _poly = [_p01, _edgeL, _edgeT] } } };
                    };
                    case 3: {
                        if (!_s00) then { _poly = [_edgeB, _p10, _p11, _p01, _edgeL] }
                        else { if (!_s10) then { _poly = [_p00, _edgeB, _edgeR, _p11, _p01] }
                        else { if (!_s11) then { _poly = [_p00, _p10, _edgeR, _edgeT, _p01] }
                        else { _poly = [_p00, _p10, _p11, _edgeT, _edgeL] } } };
                    };
                    case 2: {
                        if (_s00 && _s10) then { _poly = [_p00, _p10, _edgeR, _edgeL] }
                        else { if (_s10 && _s11) then { _poly = [_edgeB, _p10, _p11, _edgeT] }
                        else { if (_s11 && _s01) then { _poly = [_edgeL, _edgeR, _p11, _p01] }
                        else { if (_s01 && _s00) then { _poly = [_p00, _edgeB, _edgeT, _p01] }
                        else {
                            // Saddle: the two corners are diagonally opposite.
                            if (_s00) then {
                                if (_avg > 0) then { _poly = [_p00, _edgeB, _edgeR, _p11, _edgeT, _edgeL] }
                                else { (_fills select _k) append [_p00,_edgeB,_edgeL,_p11,_edgeT,_edgeR] };
                            } else {
                                if (_avg > 0) then { _poly = [_edgeB, _p10, _edgeR, _edgeT, _p01, _edgeL] }
                                else { (_fills select _k) append [_p10,_edgeR,_edgeB,_p01,_edgeL,_edgeT] };
                            };
                        } } } };
                    };
                    default {};
                };
                private _polyCount = count _poly;
                if (_polyCount >= 3) then {
                    private _first = _poly # 0;
                    for "_t" from 1 to (_polyCount - 2) do {
                        (_fills select _k) append [_first, _poly # _t, _poly # (_t + 1)];
                    };
                };
            };
        } forEach _todo;
    };

    if (_doFill && {_runSide >= 0}) then {
        (_fills select _runSide) append [[_runX,_y0],[_xRight,_y0],[_xRight,_y1],[_runX,_y0],[_xRight,_y1],[_runX,_y1]];
    };
};

// ---- 8. Publish the cache -----------------------------------------------
private _out = [];
for "_s" from 0 to _sLast do {
    _out pushBack [_sideColours select _s, _segs select _s, _fills select _s];
};
A3A_influenceSides = _out;
A3A_influenceCellSize = _cell;

Debug_5("computeInfluenceZones: range=%1m train=%2 cell=%3m grid=%4x%5 sides=%6",
    _refRange, _trainScale, round _cell, _nx, _ny, _sideCount);
