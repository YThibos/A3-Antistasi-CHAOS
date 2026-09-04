#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Derives the supply network's hard distance cap from the map itself, once at
    init, and stores it in A3A_supplyMaxEdgeAuto.

    ---- Why a derived number ----------------------------------------------
    A3A_CHAOS_supplyMaxEdge used to be a flat 1500 m constant. That is a fine
    number on Altis and a wrong one on a map whose markers are twice as far
    apart or half as far: too small and no side has a network at all, too large
    and everything meshes again. The cap is really a question about the map's
    own scale, so it is measured from the map's own geometry.

    The measurement is a minimum spanning tree over every hub-class marker,
    ownership ignored - so the number is a stable property of the terrain and
    does not flap as territory changes hands. Deliberately NOT the largest MST
    edge: that is exactly the threshold at which the map barely connects as a
    single chain with no alternate routes, so any one cut fragments the whole
    network - the opposite of what a supply network should be. A high percentile
    keeps one remote outlier marker from setting the number for the entire map,
    and the redundancy factor on top buys the alternate routes.

    The CBA slider remains the override: set it above zero and it wins outright,
    leave it at zero (the default) and this value is used.

Arguments:
    None

Return Value:
    <NUMBER> the derived cap in metres, or 0 when the map has too few markers.

Scope: Server
Environment: Unscheduled
Public: No

Publishes:
    A3A_supplyMaxEdgeAuto <NUMBER> server-side only; read by
                                   A3A_fnc_computeSupplyGraph.
*/

// ---- Tuning -------------------------------------------------------------
// Which MST edge to read off. 0.9 = the 90th-percentile edge: long enough to
// span all but the most isolated tenth of the map's links, short enough that a
// single outlier marker on a far island cannot define the cap.
#define MST_PERCENTILE 0.9
// Headroom on top of that. At exactly the percentile length the network is a
// bare chain; this is what buys the alternate routes that make severing a line
// a decision rather than an inevitability.
#define MST_REDUNDANCY 1.3

if (!isServer) exitWith {
    Error("computeMaxSupplyEdge: server-only function miscalled");
    0
};

// The same hub classes A3A_fnc_computeSupplyGraph routes through, so the cap is
// measured over the network it actually caps. Ownership is not consulted.
private _hubs = (missionNamespace getVariable ["citiesX", []])
              + (missionNamespace getVariable ["resourcesX", []])
              + (missionNamespace getVariable ["factories", []])
              + (missionNamespace getVariable ["airportsX", []])
              + (missionNamespace getVariable ["seaports", []]);

private _nodes = [];
{
    private _pos = getMarkerPos _x;
    if !(_pos isEqualTo [0,0,0]) then { _nodes pushBack _pos };
} forEach _hubs;

private _n = count _nodes;
if (_n < 3) exitWith {
    A3A_supplyMaxEdgeAuto = 0;
    Info_1("computeMaxSupplyEdge: only %1 hub markers, no cap derived", _n);
    0
};

// ---- Prim's minimum spanning tree ---------------------------------------
// Indices throughout, never positions: two markers can share a position exactly,
// and subtracting a position array by value would drop both of them.
private _inTree = [0];
private _outTree = [];
for "_i" from 1 to (_n - 1) do { _outTree pushBack _i };

private _mstEdges = [];
while { count _outTree > 0 } do {
    private _minDist = 1e11;
    private _bestPos = -1;
    {
        private _outPos = _forEachIndex;
        private _p = _nodes select _x;
        {
            private _d = _p distance2D (_nodes select _x);
            if (_d < _minDist) then { _minDist = _d; _bestPos = _outPos };
        } forEach _inTree;
    } forEach _outTree;

    if (_bestPos < 0) exitWith {};      // unreachable in practice; never spin
    _mstEdges pushBack _minDist;
    _inTree pushBack (_outTree deleteAt _bestPos);
};

if (_mstEdges isEqualTo []) exitWith {
    A3A_supplyMaxEdgeAuto = 0;
    Info("computeMaxSupplyEdge: spanning tree produced no edges");
    0
};

// ---- Percentile, then redundancy ----------------------------------------
_mstEdges sort true;
private _rank = ((ceil (MST_PERCENTILE * (count _mstEdges))) - 1) max 0 min ((count _mstEdges) - 1);
private _pct = _mstEdges select _rank;
private _cap = round (_pct * MST_REDUNDANCY);

A3A_supplyMaxEdgeAuto = _cap;
Info_4("computeMaxSupplyEdge: %1 hubs, MST longest %2 m, p%3 %4 m", _n, round (_mstEdges select ((count _mstEdges) - 1)), round (MST_PERCENTILE * 100), round _pct);
Info_1("computeMaxSupplyEdge: derived supply cap %1 m (slider at 0 = auto uses this)", _cap);

_cap
