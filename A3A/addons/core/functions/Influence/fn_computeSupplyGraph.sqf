#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the supply graph for every side from the shared influence field, and
    publishes it for the map overlay to draw.

    ---- Two tiers, not one -------------------------------------------------
    The first version made every owned zone a node, which produced a mesh: with
    ~300 nodes and a side holding most of the map, everything linked to
    everything. The structure is now explicitly two-tier, which is both far
    sparser and easier to reason about.

      HUBS      Synd_HQ, resources, factories, cities, airfields, seaports -
                plus, for the enemy sides, their off-map support corridor. These
                form the BACKBONE: a sparse hub-to-hub network, distance-capped
                and link-limited.

                Airfields and seaports are hubs on every side, the player
                included. An airfield already gates airstrikes and a seaport is
                a port of debarkation, not a leaf: both are the points at which
                supply ENTERS a theatre, which is the definition of a hub here.
                It is also the groundwork for vehicle import, which only means
                anything at a port genuinely wired into the network. There are
                only a handful of each per map and the per-hub link cap bounds
                degree structurally, so promoting them does not re-mesh the
                graph.

      SPOKES    Outposts, and only outposts. They are the numerous class - the
                reason the original flat model meshed - and they are leaves by
                design. A spoke is connected when it sits within hub range of a
                hub that is itself connected, and it hangs off that hub by a
                single line. A spoke never relays.

      NOT NODES Roadblocks and watchposts (outpostsFIA, controlsX). Never, under
                any setting. They are the player's influence-shaping tools,
                placed specifically to sever corridors; making them nodes too
                would let them repair the network they exist to cut. They still
                project influence exactly as before - that is how they sever -
                they are simply not something supply can route THROUGH.

    Player resources and factories additionally need Tier 1 (A3A_fnc_siteTiers)
    before they count as hubs at all. Enemy sites have no tiers and are always
    hubs. Cities, airfields and seaports are hubs unconditionally on every side -
    only resources and factories are tier-gated.

    ---- The enemy corridors have to be seeded -------------------------------
    An off-map support corridor sits offshore, kilometres from the nearest
    marker, with open water in between. It therefore fails the distance cap AND
    the ground test, and would be a permanently isolated root. Each enemy side
    is given explicit SEED links instead: one to its nearest owned airfield and
    one to its nearest owned seaport, chosen by distance from the corridor so
    they stay local. Seeds skip the ground test - you cannot interdict open
    water with a roadblock - but they are not unconditional: they exist only
    while that side still owns that port or airfield, so capturing one severs
    the region behind it. A side owning neither degrades to its nearest owned
    city rather than collapsing to zero supply, which matters because unsupplied
    status stacks with the vanilla no-airport penalty in fn_aggressionUpdateLoop.

    ---- Why the backbone is capped twice ----------------------------------
    The candidate test asks whether two zones' outer cones could overlap, which
    at Altis defaults reaches 4 km outpost-to-outpost. That is a fine "could
    these be linked" test and a hopeless "is this a network" one. A hard metre
    cap kills the cross-map links; a per-hub link limit thins the dense clusters
    that survive it. The link limit is applied AFTER the corridor test and as a
    symmetric union, so a pruned edge is one that was genuinely available and
    lost to nearer neighbours, never one that failed on the ground, and no hub on
    the rim of a cluster is stranded because its neighbours all have closer
    company.

Arguments:
    None

Return Value:
    <BOOL> true when a graph was built.

Scope: Server
Environment: Unscheduled
Public: No

Publishes:
    A3A_supplyEdges      <ARRAY>   [[markerA, markerB, side, isSpoke], ...] every side
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

// ---- Settings -----------------------------------------------------------
// The slider is an explicit override: above zero it wins outright, at zero (the
// default) the per-map value A3A_fnc_computeMaxSupplyEdge derived at init is
// used. Writing the slider's own variable from init would silently override the
// captain's setting and fight CBA's broadcast, so the derived value lives in its
// own variable and the choice is made here.
private _maxEdge = missionNamespace getVariable ["A3A_CHAOS_supplyMaxEdge", 0];
if !(_maxEdge isEqualType 0 && {_maxEdge > 0}) then {
    _maxEdge = missionNamespace getVariable ["A3A_supplyMaxEdgeAuto", 0];
};
// Neither set: the map was too small to measure, or init has not run yet.
if !(_maxEdge isEqualType 0 && {_maxEdge > 0}) then { _maxEdge = 1500 };

private _maxLinks = missionNamespace getVariable ["A3A_CHAOS_supplyMaxLinks", 3];
if !(_maxLinks isEqualType 0 && {_maxLinks >= 1}) then { _maxLinks = 3 };
_maxLinks = round _maxLinks;

private _hubRange = missionNamespace getVariable ["A3A_CHAOS_supplyHubRange", 1500];
if !(_hubRange isEqualType 0 && {_hubRange > 0}) then { _hubRange = 1500 };

// Corridor sampling
private _sampleStep = 250;
private _samplesMin = 5;
private _samplesMax = 16;

// ---- Node classification ------------------------------------------------
private _tiers = call A3A_fnc_siteTiers;
private _resources = missionNamespace getVariable ["resourcesX", []];
private _factories = missionNamespace getVariable ["factories", []];
private _cities    = missionNamespace getVariable ["citiesX", []];
private _outposts  = missionNamespace getVariable ["outposts", []];
private _airports  = missionNamespace getVariable ["airportsX", []];
private _seaports  = missionNamespace getVariable ["seaports", []];

private _tierGated = _resources + _factories;
private _spokeMarkers = _outposts;
private _portMarkers = _airports + _seaports;
private _carriers = ["NATO_carrier", "CSAT_carrier"];

// Shared corridor test. Returns true when NO interior sample along the segment is
// dominated by a side hostile to this one. Endpoints are deliberately not
// sampled: they are zone centres, trivially owned, and testing them would mask a
// cut right at the shoulder of a zone.
//
// This used to demand that every sample be OWNED by the side, which is the wrong
// model twice over. Militarily you do not need to hold every metre of a road,
// you need it not to be interdicted; mechanically, a map-spanning occupier's
// backbone died the moment it crossed empty wilderness, which is most of Altis.
// Roadblocks and watchposts sever exactly as before, because they sever by
// projecting HOSTILE influence across the corridor, and that still fails here.
//
// A3A_fnc_influenceAt returns -1 for ground no side reaches and for an exact tie
// between two sides. Both are neutral, not hostile, so both pass - which is why
// this tests membership in an explicit hostile-index list rather than comparing
// against the side's own index.
private _fnc_corridorOk = {
    params ["_ax", "_ay", "_bx", "_by", "_dist", "_hostileIdxs"];
    private _samples = (round (_dist / _sampleStep)) max _samplesMin min _samplesMax;
    private _ok = true;
    for "_s" from 1 to _samples do {
        private _t = _s / (_samples + 1);
        private _sx = _ax + (_bx - _ax) * _t;
        private _sy = _ay + (_by - _ay) * _t;
        private _owner = ([_ctx, [_sx, _sy]] call A3A_fnc_influenceAt) # 0;
        if (_owner in _hostileIdxs) exitWith { _ok = false };
    };
    _ok
};

// The three Antistasi factions are mutually hostile by construction, so hostility
// is "a different one of the three". Anything else that ends up in _sideList -
// civilians, say - is neutral ground and does not cut a line.
private _fightingSides = [teamPlayer];
if !(isNil "Occupants") then { _fightingSides pushBackUnique Occupants };
if !(isNil "Invaders")  then { _fightingSides pushBackUnique Invaders };

private _ratios = createHashMap;
private _allEdges = [];
private _playerConnected = [];

{
    private _sideIdx = _forEachIndex;
    private _side = _sideList select _sideIdx;
    private _zones = _sideZones select _sideIdx;
    private _isPlayer = _side isEqualTo teamPlayer;

    private _hostileIdxs = [];
    {
        if (!(_x isEqualTo _side) && {_x in _fightingSides}) then { _hostileIdxs pushBack _forEachIndex };
    } forEach _sideList;

    // ---- Split this side's zones into hubs and spokes -------------------
    private _hubs = [];
    private _spokes = [];
    {
        private _mrk = _x # 3;
        if (_mrk in _spokeMarkers) then { _spokes pushBack _x; continue };

        private _isHub = (_mrk isEqualTo "Synd_HQ")
                      || {_mrk in _cities}
                      || {_mrk in _portMarkers}
                      || {_mrk in _carriers}
                      || {_mrk in _tierGated};

        if (!_isHub) then { continue };     // roadblocks, watchposts: never nodes

        // Player resource/factory hubs need Tier 1. Enemy sites have no tiers.
        if (_isPlayer && {_mrk in _tierGated} && {(_tiers getOrDefault [_mrk, 0]) < 1}) then { continue };

        _hubs pushBack _x;
    } forEach _zones;

    if (_hubs isEqualTo []) then {
        _ratios set [_side, 0];
        Debug_1("computeSupplyGraph: side %1 has no hubs", _side);
        continue;
    };

    // ---- Enemy corridor seed links --------------------------------------
    // The corridor is offshore and would otherwise be an isolated root: too far
    // from any marker for the distance cap, with open water in between that no
    // ground test can pass. It is seeded to the nearest airfield and the nearest
    // seaport this side actually owns - one of each, nearest by distance from the
    // corridor, so the network starts local instead of reaching across the map.
    // If the side owns neither, it degrades to its nearest owned city.
    //
    // Seeds are index pairs into _hubs, exempt from the ground test and from the
    // link pruning, but never unconditional: they are rebuilt from CURRENT
    // ownership on every pass, so taking the port takes the link with it.
    private _seedEdges = [];
    if (!_isPlayer) then {
        private _carrierIdx = _hubs findIf { (_x # 3) in _carriers };
        if (_carrierIdx >= 0) then {
            (_hubs select _carrierIdx) params ["_cx", "_cy"];

            // Nearest hub of each class, by distance from the corridor.
            private _fnc_nearestOf = {
                params ["_classMarkers"];
                private _bestIdx = -1;
                private _bestDist = 1e11;
                {
                    if (_forEachIndex != _carrierIdx && {(_x # 3) in _classMarkers}) then {
                        private _d = sqrt ((((_x # 0) - _cx) ^ 2) + (((_x # 1) - _cy) ^ 2));
                        if (_d < _bestDist) then { _bestDist = _d; _bestIdx = _forEachIndex };
                    };
                } forEach _hubs;
                [_bestIdx, _bestDist]
            };

            ([_airports] call _fnc_nearestOf) params ["_airIdx", "_airDist"];
            ([_seaports] call _fnc_nearestOf) params ["_seaIdx", "_seaDist"];

            if (_airIdx >= 0) then {
                _seedEdges pushBack [_carrierIdx, _airIdx, _airDist];
                Debug_3("computeSupplyGraph: side %1 corridor seeded to airfield %2 at %3 m", _side, (_hubs select _airIdx) # 3, round _airDist);
            };
            if (_seaIdx >= 0) then {
                _seedEdges pushBack [_carrierIdx, _seaIdx, _seaDist];
                Debug_3("computeSupplyGraph: side %1 corridor seeded to seaport %2 at %3 m", _side, (_hubs select _seaIdx) # 3, round _seaDist);
            };

            if (_seedEdges isEqualTo []) then {
                ([_cities] call _fnc_nearestOf) params ["_cityIdx", "_cityDist"];
                if (_cityIdx >= 0) then {
                    _seedEdges pushBack [_carrierIdx, _cityIdx, _cityDist];
                    Debug_3("computeSupplyGraph: side %1 holds no port or airfield - corridor seeded to city %2 at %3 m", _side, (_hubs select _cityIdx) # 3, round _cityDist);
                } else {
                    Debug_1("computeSupplyGraph: side %1 has nothing to seed its corridor to", _side);
                };
            };
        };
    };

    // ---- Backbone candidates --------------------------------------------
    private _cands = [];
    private _hubCount = count _hubs;
    for "_a" from 0 to (_hubCount - 2) do {
        (_hubs select _a) params ["_ax", "_ay", "_ar"];
        for "_b" from (_a + 1) to (_hubCount - 1) do {
            (_hubs select _b) params ["_bx", "_by", "_br"];
            private _dx = _bx - _ax;
            private _dy = _by - _ay;
            private _d2 = _dx * _dx + _dy * _dy;
            private _lim = ((_ar + _br) * _reachMult) min _maxEdge;
            if (_d2 <= _lim * _lim) then {
                // Never generate a candidate that a seed already covers, or the
                // pair would be emitted twice.
                private _dupe = _seedEdges findIf {
                    private _u = _x # 0;
                    private _v = _x # 1;
                    ((_u == _a) && {_v == _b}) || {(_u == _b) && {_v == _a}}
                };
                if (_dupe < 0) then {
                    _cands pushBack [_a, _b, sqrt _d2];
                };
            };
        };
    };

    // ---- Corridor test --------------------------------------------------
    private _survivors = [];
    {
        _x params ["_a", "_b", "_dist"];
        (_hubs select _a) params ["_ax", "_ay"];
        (_hubs select _b) params ["_bx", "_by"];
        if ([_ax, _ay, _bx, _by, _dist, _hostileIdxs] call _fnc_corridorOk) then {
            _survivors pushBack [_a, _b, _dist];
        };
    } forEach _cands;

    // ---- Prune to the nearest _maxLinks per hub -------------------------
    private _incident = [];
    { _incident pushBack [] } forEach _hubs;
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
            // Repeated minimum selection: _maxLinks is small, and this avoids
            // BIS_fnc_sortBy, whose algorithm block would fail by silently
            // mis-ordering rather than by erroring.
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

    // Seeds join the survivor list only now, already kept: they must not be
    // eligible for pruning, or a busy port could drop the one link that feeds it.
    {
        _survivors pushBack _x;
        _keep pushBack true;
    } forEach _seedEdges;

    private _adj = [];
    { _adj pushBack [] } forEach _hubs;
    {
        if (_keep select _forEachIndex) then {
            _x params ["_a", "_b"];
            (_adj select _a) pushBack _b;
            (_adj select _b) pushBack _a;
        };
    } forEach _survivors;

    // ---- Root -----------------------------------------------------------
    // The player is rooted at the HQ. Each enemy side is rooted at its off-map
    // support corridor, which is what an occupying army actually is: supply
    // flows in from off the map, so cutting inland from the coast severs
    // everything behind the cut.
    private _rootIdx = -1;
    if (_isPlayer) then {
        _rootIdx = _hubs findIf { (_x # 3) isEqualTo "Synd_HQ" };
    } else {
        _rootIdx = _hubs findIf { (_x # 3) in _carriers };
    };
    if (_rootIdx < 0) then {
        // No carrier or no HQ in the hub set: fall back to the largest holding
        // so a side is never left with an empty network by accident.
        private _bestR = -1;
        { if ((_x # 2) > _bestR) then { _bestR = _x # 2; _rootIdx = _forEachIndex } } forEach _hubs;
    };

    // ---- Breadth-first walk ---------------------------------------------
    private _seen = [];
    { _seen pushBack false } forEach _hubs;
    private _connectedHubs = [];

    if (_rootIdx >= 0) then {
        _seen set [_rootIdx, true];
        private _queue = [_rootIdx];
        private _head = 0;
        while { _head < count _queue } do {
            private _cur = _queue select _head;
            _head = _head + 1;
            _connectedHubs pushBack _cur;
            {
                if !(_seen select _x) then {
                    _seen set [_x, true];
                    _queue pushBack _x;
                };
            } forEach (_adj select _cur);
        };
    };

    // ---- Emit backbone edges between connected hubs ---------------------
    private _connected = [];
    { _connected pushBack ((_hubs select _x) # 3) } forEach _connectedHubs;

    {
        if (_keep select _forEachIndex) then {
            _x params ["_a", "_b"];
            if (_seen select _a) then {
                _allEdges pushBack [(_hubs select _a) # 3, (_hubs select _b) # 3, _side, false];
            };
        };
    } forEach _survivors;

    // ---- Spokes ---------------------------------------------------------
    // Each spoke hangs off the nearest CONNECTED hub within range, if the
    // corridor to it holds. One line each - a spoke never relays.
    {
        _x params ["_sx", "_sy", "", "_sMrk"];
        private _bestIdx = -1;
        private _bestDist = _hubRange;
        {
            (_hubs select _x) params ["_hx", "_hy"];
            private _d = sqrt (((_hx - _sx) ^ 2) + ((_hy - _sy) ^ 2));
            if (_d <= _bestDist) then { _bestDist = _d; _bestIdx = _x };
        } forEach _connectedHubs;

        if (_bestIdx >= 0) then {
            (_hubs select _bestIdx) params ["_hx", "_hy"];
            if ([_sx, _sy, _hx, _hy, _bestDist, _hostileIdxs] call _fnc_corridorOk) then {
                _connected pushBack _sMrk;
                _allEdges pushBack [_sMrk, (_hubs select _bestIdx) # 3, _side, true];
            };
        };
    } forEach _spokes;

    private _owned = (count _hubs) + (count _spokes);
    _ratios set [_side, if (_owned > 0) then { (count _connected) / _owned } else { 0 }];

    if (_isPlayer) then { _playerConnected = _connected };

    // Hub composition is logged as well as the total: promoting airfields and
    // seaports is the change most likely to surprise on an unfamiliar map, and
    // "how many hubs did that actually produce" is the number to sanity-check.
    private _portHubs = count (_hubs select { (_x # 3) in _portMarkers });
    Debug_5("computeSupplyGraph: side %1 - %2 hubs (%3 ports/airfields), %4 spokes, %5 connected", _side, count _hubs, _portHubs, count _spokes, count _connected);

} forEach _sideZones;

A3A_supplyRatios = _ratios;

A3A_supplyEdges = _allEdges;
publicVariable "A3A_supplyEdges";
A3A_supplyConnected = _playerConnected;
publicVariable "A3A_supplyConnected";

A3A_supplyGraphMs = (diag_tickTime - _tStart) * 1000;
Debug_2("computeSupplyGraph: %1 edges in %2 ms", count _allEdges, A3A_supplyGraphMs);

true
