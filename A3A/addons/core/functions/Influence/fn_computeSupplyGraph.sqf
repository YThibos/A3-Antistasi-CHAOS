#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the supply graph for every side from the shared influence field, and
    publishes the player faction's half of it for the map overlay to draw.

    ---- The model -----------------------------------------------------------
    Zones are nodes. Two zones of the same side are CANDIDATES for an edge when
    they are close enough that their outer cones could overlap:

        distance(A, B) <= (R(A) + R(B)) * reachMult

    A candidate becomes a real edge only when the CORRIDOR between them stays
    that side's ground: the segment is sampled at a handful of points and every
    sample must come back owned by that side from A3A_fnc_influenceAt. So an
    enemy who pushes influence across the corridor severs the link, exactly as
    a player reading the border would expect - which is the whole reason the
    field evaluation is shared rather than reimplemented here.

    Supply reach is then a breadth-first walk from the side's root node over
    surviving edges. Everything the walk does not reach is cut off, and islands
    fall out for free.

    ---- Why the outer radius, not the real one ------------------------------
    The candidate test uses reachMult, the same multiplier the faint long cone
    uses, because that cone is what makes distant holdings look contiguous on
    the map. Testing with the bare radii would refuse edges between zones the
    player can plainly see joined up. The corridor test is the real gate; the
    candidate test only decides what is worth testing.

    ---- What is published, and what is not ----------------------------------
    Only the player faction's edges and connected set go out over the network.
    Enemy connectivity stays server-side and is consumed by
    fn_aggressionUpdateLoop as a rate multiplier. That is deliberate: publishing
    enemy edges would hand every client a live map of the enemy supply network
    with no scouting, and how enemy lines should become visible (captured
    intel, interrogation) is a design decision that has not been made yet.

    ---- Cost ---------------------------------------------------------------
    The candidate scan is O(n^2) per side in squared-distance tests, which is
    cheap; the corridor sampling is the real cost and is bounded by
    _sampleBudget - past that the samples per edge fall to the floor rather
    than the function bailing out, so a very large map degrades to a coarser
    corridor test instead of losing the graph. This runs on territory change
    (debounced) and on the 10-minute resource tick, never per frame.

    NOT VERIFIED IN GAME: the cost figures above are reasoned from the array
    sizes, not measured. Watch A3A_supplyGraphMs in the RPT on a populated map.

Arguments:
    None

Return Value:
    <BOOL> true when a graph was built, false when the zone data was not ready.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_influenceContext, A3A_fnc_influenceAt
    airportsX, outposts, citiesX, teamPlayer, Occupants, Invaders  (globals)

Publishes:
    A3A_supplyEdges      <ARRAY>   [[markerA, markerB], ...] player side only
    A3A_supplyConnected  <ARRAY>   player-side markers reachable from the HQ
    A3A_supplyRatios     <HASHMAP> side -> connected/owned, server-side only
*/

if (!isServer) exitWith {
    Error("computeSupplyGraph: server-only function miscalled");
    false
};

private _tStart = diag_tickTime;

private _ctx = call A3A_fnc_influenceContext;
if (_ctx isEqualTo []) exitWith {
    Debug("computeSupplyGraph: no influence context yet");
    false
};

_ctx params ["_sideList", "_sideZones", "_consts"];
_consts params ["", "", "", "", "_reachMult"];

// ---- Tier gate on the player's own resources and factories --------------
// A rebel resource or factory only joins the graph once it has been upgraded
// to Tier 1. Below that it is not a node at all: it can neither be supplied
// nor relay supply through itself. Its vanilla income is untouched - the tier
// ladder is upside, never a tax (see A3A_fnc_siteTier).
//
// This filter lives here and NOT in A3A_fnc_influenceContext on purpose. The
// context is the influence FIELD, and a Tier 0 resource still projects
// influence and still draws its share of the border exactly as before;
// removing it there would silently redraw the map. Topology and field are
// different questions asked of the same data.
//
// Enemy-held resources and factories are unaffected: tiers are a Guerilla
// mechanic and the enemy has no equivalent, so gating their nodes on a tier
// they can never have would sever their networks for free.
private _tiers = call A3A_fnc_siteTiers;
private _tierGated = (missionNamespace getVariable ["resourcesX", []])
                   + (missionNamespace getVariable ["factories", []]);

private _playerIdx = _sideList find teamPlayer;
if (_playerIdx >= 0) then {
    private _before = count (_sideZones select _playerIdx);
    _sideZones set [_playerIdx, (_sideZones select _playerIdx) select {
        private _mrk = _x # 3;
        !(_mrk in _tierGated) || {(_tiers getOrDefault [_mrk, 0]) > 0}
    }];
    private _after = count (_sideZones select _playerIdx);
    if (_after < _before) then {
        Debug_2("computeSupplyGraph: %1 of %2 rebel sites held back at Tier 0", _before - _after, _before);
    };
};

// ---- Tunables -----------------------------------------------------------
private _sampleStep   = 250;    // metres between corridor samples, before budgeting
private _samplesMin   = 5;
private _samplesMax   = 16;
private _sampleBudget = 60000;  // total corridor samples across every side

// ---- Sparsification: why the radius test alone is not enough ------------
// The candidate test asks whether two zones' outer cones could overlap, which on
// Altis at the defaults reaches 4 km between outposts and 5.6 km airfield to
// airfield. That is a fine test for "could these be linked", and a hopeless one
// for "is this a supply network": once a side holds most of the map, the
// corridor between ANY two of its zones is its own ground, every candidate
// passes, and the graph degenerates into a near-complete mesh - measured in game
// as a solid fan of lines from every marker to every other one.
//
// Two limits turn it back into a network. A hard metre cap kills the cross-map
// links the radius test allows, and a per-node link limit thins the dense
// clusters that survive the cap. Both are settings, because the right numbers
// depend on how a given map spaces its objectives.
//
// The link limit is applied AFTER the corridor test, so a pruned edge is one
// that was genuinely available and simply lost to nearer neighbours - never one
// that failed on the ground. It is a symmetric union: A keeping B always yields
// an edge, whether or not B would have kept A, so no node is left stranded
// merely because its neighbours are all in a denser cluster than it is.
private _maxEdge = missionNamespace getVariable ["A3A_CHAOS_supplyMaxEdge", 1500];
if !(_maxEdge isEqualType 0 && {_maxEdge > 0}) then { _maxEdge = 1500 };

private _maxLinks = missionNamespace getVariable ["A3A_CHAOS_supplyMaxLinks", 3];
if !(_maxLinks isEqualType 0 && {_maxLinks >= 1}) then { _maxLinks = 3 };
_maxLinks = round _maxLinks;

private _ratios = createHashMap;
private _playerEdges = [];
private _playerConnected = [];

// ---- Pass 1: candidate edges, so the sample budget can be shared ---------
// Collected per side as [_aIdx, _bIdx, _distance]; the corridor test in pass 2
// spends the budget across all of them rather than letting the first side
// exhaust it.
private _candidates = [];
private _candidateCount = 0;

{
    private _zones = _x;
    private _n = count _zones;
    private _sideCands = [];

    for "_a" from 0 to (_n - 2) do {
        (_zones select _a) params ["_ax", "_ay", "_ar"];
        for "_b" from (_a + 1) to (_n - 1) do {
            (_zones select _b) params ["_bx", "_by", "_br"];
            private _dx = _bx - _ax;
            private _dy = _by - _ay;
            private _d2 = _dx * _dx + _dy * _dy;
            // Whichever is tighter: the cones-could-overlap test, or the hard cap.
            private _lim = ((_ar + _br) * _reachMult) min _maxEdge;
            if (_d2 <= _lim * _lim) then {
                _sideCands pushBack [_a, _b, sqrt _d2];
            };
        };
    };

    _candidates pushBack _sideCands;
    _candidateCount = _candidateCount + count _sideCands;
} forEach _sideZones;

// If even the floor density would blow the budget, every edge drops to the
// floor rather than the function bailing out: a coarser corridor test still
// severs on a real push across the line, where no graph at all would strand
// every faction at full rate and quietly disable the whole feature.
private _denseSampling = true;
if (_candidateCount * _samplesMin > _sampleBudget) then {
    _denseSampling = false;
    Debug_2("computeSupplyGraph: %1 candidates over budget %2 - sampling at the floor", _candidateCount, _sampleBudget);
};

// ---- Pass 2: corridor test, then BFS, per side --------------------------
private _samplesTaken = 0;

{
    private _sideIdx = _forEachIndex;
    private _side = _sideList select _sideIdx;
    private _zones = _sideZones select _sideIdx;
    private _sideCands = _candidates select _sideIdx;

    // Adjacency by zone index, so the BFS never touches marker strings.
    private _adj = [];
    { _adj pushBack [] } forEach _zones;

    // Edges that passed the corridor test, as [_a, _b, _dist], before pruning.
    private _survivors = [];

    {
        _x params ["_a", "_b", "_dist"];
        (_zones select _a) params ["_ax", "_ay"];
        (_zones select _b) params ["_bx", "_by"];

        private _samples = _samplesMin;
        if (_denseSampling) then {
            _samples = (round (_dist / _sampleStep)) max _samplesMin min _samplesMax;
        };

        // Interior samples only: both endpoints are zone centres and are
        // trivially owned by their own side, so testing them proves nothing
        // and would mask a corridor cut right at the shoulder of a zone.
        private _ok = true;
        for "_s" from 1 to _samples do {
            private _t = _s / (_samples + 1);
            private _sx = _ax + (_bx - _ax) * _t;
            private _sy = _ay + (_by - _ay) * _t;
            private _owner = ([_ctx, [_sx, _sy]] call A3A_fnc_influenceAt) # 0;
            _samplesTaken = _samplesTaken + 1;
            if (_owner != _sideIdx) exitWith { _ok = false };
        };

        if (_ok) then { _survivors pushBack [_a, _b, _dist] };
    } forEach _sideCands;

    // ---- Prune to the nearest _maxLinks per node ------------------------
    // Each node nominates its own nearest surviving edges; an edge is kept if
    // EITHER endpoint nominated it. Without the union a node on the rim of a
    // dense cluster loses every link, because each of its neighbours has closer
    // company - which would cut off exactly the outlying sites the network is
    // supposed to reach.
    private _incident = [];
    { _incident pushBack [] } forEach _zones;
    {
        _x params ["_a", "_b"];
        (_incident select _a) pushBack _forEachIndex;
        (_incident select _b) pushBack _forEachIndex;
    } forEach _survivors;

    private _keep = [];
    { _keep pushBack false } forEach _survivors;
    {
        private _edgeIdxs = _x;
        if (count _edgeIdxs <= _maxLinks) then {
            { _keep set [_x, true] } forEach _edgeIdxs;
        } else {
            // Nominate the _maxLinks shortest by repeated minimum selection rather
            // than a sort. _maxLinks is 3 by default, so this is a handful of passes
            // over a short list - and it avoids BIS_fnc_sortBy, whose algorithm block
            // has a calling convention that is easy to get subtly wrong and that
            // would fail by silently mis-ordering rather than by erroring.
            private _remaining = +_edgeIdxs;
            for "_n" from 1 to _maxLinks do {
                if (_remaining isEqualTo []) exitWith {};
                private _bestPos = 0;
                private _bestLen = (_survivors select (_remaining select 0)) # 2;
                {
                    private _len = (_survivors select _x) # 2;
                    if (_len < _bestLen) then { _bestLen = _len; _bestPos = _forEachIndex };
                } forEach _remaining;
                _keep set [_remaining deleteAt _bestPos, true];
            };
        };
    } forEach _incident;

    private _pruned = 0;
    {
        if (_keep select _forEachIndex) then {
            _x params ["_a", "_b"];
            (_adj select _a) pushBack _b;
            (_adj select _b) pushBack _a;
        } else {
            _pruned = _pruned + 1;
        };
    } forEach _survivors;

    if (_pruned > 0) then {
        Debug_3("computeSupplyGraph: side %1 kept %2 edges, pruned %3 to the link limit", _side, (count _survivors) - _pruned, _pruned);
    };

    // ---- Root node ------------------------------------------------------
    // The player faction is rooted at the HQ, which is the whole point of the
    // design: the network hangs off wherever Petros is standing. Every other
    // side is rooted at its most valuable holding, re-picked every rebuild so
    // that losing a capital moves the root instead of killing the network.
    private _rootIdx = -1;
    if (_side isEqualTo teamPlayer) then {
        _rootIdx = _zones findIf { (_x # 3) isEqualTo "Synd_HQ" };
    };
    if (_rootIdx < 0) then {
        private _airports = missionNamespace getVariable ["airportsX", []];
        _rootIdx = _zones findIf { (_x # 3) in _airports };
    };
    if (_rootIdx < 0) then {
        private _outposts = missionNamespace getVariable ["outposts", []];
        _rootIdx = _zones findIf { (_x # 3) in _outposts };
    };
    if (_rootIdx < 0) then {
        // Largest holding by influence radius: the best proxy for "capital"
        // when a side owns neither an airfield nor an outpost.
        private _bestR = -1;
        {
            if ((_x # 2) > _bestR) then { _bestR = _x # 2; _rootIdx = _forEachIndex };
        } forEach _zones;
    };

    // ---- Breadth-first walk from the root -------------------------------
    private _seen = [];
    { _seen pushBack false } forEach _zones;
    private _connected = [];

    if (_rootIdx >= 0) then {
        _seen set [_rootIdx, true];
        private _queue = [_rootIdx];
        private _head = 0;
        while { _head < count _queue } do {
            private _cur = _queue select _head;
            _head = _head + 1;
            _connected pushBack ((_zones select _cur) # 3);
            {
                if !(_seen select _x) then {
                    _seen set [_x, true];
                    _queue pushBack _x;
                };
            } forEach (_adj select _cur);
        };
    };

    private _owned = count _zones;
    private _ratio = if (_owned > 0) then { (count _connected) / _owned } else { 0 };
    _ratios set [_side, _ratio];

    if (_side isEqualTo teamPlayer) then {
        _playerConnected = _connected;
        // Edges are emitted by marker name for the overlay, which knows nothing
        // about this function's zone indices.
        {
            private _a = _forEachIndex;
            {
                // Each undirected edge is stored twice in _adj; emit once.
                if (_x > _a) then {
                    _playerEdges pushBack [(_zones select _a) # 3, (_zones select _x) # 3];
                };
            } forEach _x;
        } forEach _adj;
    };

    Debug_3("computeSupplyGraph: side %1 - %2 of %3 zones connected", _side, count _connected, _owned);
} forEach _sideZones;

A3A_supplyRatios = _ratios;

A3A_supplyEdges = _playerEdges;
publicVariable "A3A_supplyEdges";
A3A_supplyConnected = _playerConnected;
publicVariable "A3A_supplyConnected";

A3A_supplyGraphMs = (diag_tickTime - _tStart) * 1000;
Debug_3("computeSupplyGraph: %1 candidates, %2 samples, %3 ms", _candidateCount, _samplesTaken, A3A_supplyGraphMs);

true
