#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Computes client-side map overlay data for the influence zone visualiser and
    stores the results in two globals consumed by A3A_GUI_fnc_mapDrawInfluenceEH:

      A3A_influenceEllipses  – array of [pos, semiA, semiB, angle] for every
                                teamPlayer-owned capturable zone.
      A3A_influenceTriangles – array of [[posA, posB, posC], ...] for every
                                valid compact triangle of friendly zones that is
                                reachable from HQ through a configurable-distance
                                proximity graph AND whose interior contains no
                                enemy marker/city centre.

    Triangle validity rules:
      1. All three nodes are in the BFS-connected component starting at Synd_HQ
         (edges = pairwise distance ≤ A3A_CHAOS_influenceTriangleDist between
         teamPlayer zones; snapped to nearest 100 m, default 2 000 m).
      2. All three pairwise distances ≤ that same threshold (strict all-pairs check).
      3. No enemy-side capturable marker or city has its centre inside the
         triangle polygon (checked with inPolygon).

Arguments:
    None

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    citiesX, airportsX, resourcesX, factories, outposts, seaports, outpostsFIA,
    sidesX, teamPlayer  (all public globals, available on clients after initZones)
    A3A_CHAOS_influenceTriangleDist  (CBA setting, default 2000)
*/

// ── 0. Guard: bail out if the game globals are not yet broadcast ──────────
// markersX is the last array composed in fn_initZones, so it being non-nil
// implies airportsX, citiesX, outposts, etc. are all available.
if (isNil "markersX" || isNil "outpostsFIA" || isNil "sidesX") exitWith {
    Debug("computeInfluenceZones: zone globals not ready yet — skipping");
    A3A_influenceEllipses   = [];
    A3A_influenceTriangles  = [];
};

// ── 1. Read configurable distance threshold ───────────────────────────────
// Snap to nearest 100 m; clamp to valid range in case the CBA var is unset
private _maxDist = (round ((missionNamespace getVariable ["A3A_CHAOS_influenceTriangleDist", 2000]) / 100)) * 100;
_maxDist = (_maxDist max 1000) min 5000;

// ── 2. Ellipses: every friendly capturable zone ───────────────────────────
// markersX = airportsX + resourcesX + factories + outposts + seaports +
//            ["Synd_HQ"] + citiesX  (sorted by ascending size by initZones)
// outpostsFIA is separate (watchposts/roadblocks, 30 m fixed radius).
private _allCapturable = markersX + outpostsFIA;

private _ellipses = [];
{
    if (sidesX getVariable [_x, sideUnknown] != teamPlayer) then { continue };
    private _pos = getMarkerPos _x;
    // Skip markers that don't exist on this client (createMarkerLocal on server only)
    if (_pos isEqualTo [0,0,0]) then { continue };

    private _sA = 0;
    private _sB = 0;
    if (_x == "Synd_HQ") then {
        // Show the HQ build radius (depends on tierWar being broadcast; safe fallback to 75m)
        _sA = if (!isNil "tierWar") then { call A3A_fnc_hqBuildRadius } else { 75 };
        _sB = _sA;
    } else if (_x in outpostsFIA) then {
        _sA = 30; _sB = 30;    // hardcoded: marker created with createMarkerLocal [30,30]
    } else {
        private _sz = markerSize _x;
        _sA = _sz # 0;
        _sB = _sz # 1;
    };
    if (_sA <= 0 or _sB <= 0) then { continue };

    _ellipses pushBack [_pos, _sA, _sB, markerDir _x];
} forEach _allCapturable;

A3A_influenceEllipses = _ellipses;

// ── 3. Triangles: BFS from HQ, then all-pairs triplet search ─────────────
private _friendlySet = _allCapturable select {
    sidesX getVariable [_x, sideUnknown] == teamPlayer
    && { !(getMarkerPos _x isEqualTo [0,0,0]) }
};

// Safety cap: very marker-dense maps would make O(n³) painful
if (count _friendlySet > 80) then {
    Info_1("computeInfluenceZones: %1 friendly zones — triangle pass skipped (cap 80)", count _friendlySet);
    A3A_influenceTriangles = [];
} else {
    if !("Synd_HQ" in _friendlySet) then {
        // HQ not in friendly set — no connected component to start from
        A3A_influenceTriangles = [];
    } else {
        // BFS from Synd_HQ through ≤ _maxDist edges
        private _reachable = ["Synd_HQ"];
        private _processIdx = 0;
        while { _processIdx < count _reachable } do {
            private _curPos = getMarkerPos (_reachable # _processIdx);
            _processIdx = _processIdx + 1;
            {
                if (_x in _reachable) then { continue };
                if (_curPos distance2D (getMarkerPos _x) > _maxDist) then { continue };
                _reachable pushBack _x;
            } forEach _friendlySet;
        };

        // Pre-cache positions to avoid repeated getMarkerPos calls in the triple loop
        private _posList = _reachable apply { getMarkerPos _x };
        private _n = count _reachable;

        // Enemy positions for interior check: all capturable non-player zones
        // Use markersX which already includes cities, airports, resources, etc.
        private _enemyPosArr = markersX
            select { sidesX getVariable [_x, sideUnknown] != teamPlayer }
            apply  { getMarkerPos _x }
            select { !(_x isEqualTo [0,0,0]) };   // skip markers absent on this client

        private _triangles = [];

        for "_i" from 0 to (_n - 1) do {
            private _pA = _posList # _i;
            for "_j" from (_i + 1) to (_n - 1) do {
                private _pB = _posList # _j;
                if (_pA distance2D _pB > _maxDist) then { continue };
                for "_k" from (_j + 1) to (_n - 1) do {
                    private _pC = _posList # _k;
                    if (_pA distance2D _pC > _maxDist) then { continue };
                    if (_pB distance2D _pC > _maxDist) then { continue };
                    // All 3 pairs within threshold — check interior for enemy content
                    private _poly = [_pA, _pB, _pC];
                    if (_enemyPosArr findIf { _x inPolygon _poly } != -1) then { continue };
                    _triangles pushBack _poly;
                };
            };
        };

        A3A_influenceTriangles = _triangles;
        Debug_3("computeInfluenceZones: dist=%1 m, %2 reachable nodes, %3 valid triangles", _maxDist, _n, count _triangles);
    };
};
