#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the supply graph for every side from the shared influence field, and
    publishes the player faction's half of it for the map overlay to draw.
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
private _tiers = call A3A_fnc_siteTiers;
private _tierGated = (missionNamespace getVariable ["resourcesX", []])
                   + (missionNamespace getVariable ["factories", []]);

// ---- Exclude non-nodes (roadblocks, watchposts) from the graph natively -
private _nonNodes = (missionNamespace getVariable ["controlsX", []])
                  + (missionNamespace getVariable ["outpostsFIA", []]);

private _sideFallback = {
    params ["_fbSide"];
    if (_fbSide isEqualTo teamPlayer) exitWith { [0, 0.5, 0] };
    if (!isNil "Occupants" && {_fbSide isEqualTo Occupants}) exitWith { [0, 0.3, 0.6] };
    if (!isNil "Invaders" && {_fbSide isEqualTo Invaders}) exitWith { [0.5, 0, 0] };
    [0.45, 0.45, 0.45]
};

{
    private _side = _x;
    private _sideIdx = _forEachIndex;
    private _before = count (_sideZones select _sideIdx);
    
    _sideZones set [_sideIdx, (_sideZones select _sideIdx) select {
        private _mrk = _x # 3;
        if (_mrk in _nonNodes) then { false } else {
            if (_side isEqualTo teamPlayer && _mrk in _tierGated) then {
                (_tiers getOrDefault [_mrk, 0]) > 0
            } else { true }
        }
    }];
    
    private _after = count (_sideZones select _sideIdx);
    if (_after < _before) then {
        Debug_2("computeSupplyGraph: %1 of %2 zones held back", _before - _after, _before);
    };
} forEach _sideList;

// ---- Tunables -----------------------------------------------------------
private _sampleStep   = 250;
private _samplesMin   = 5;
private _samplesMax   = 16;
private _sampleBudget = 60000;

private _maxEdge = missionNamespace getVariable ["A3A_CHAOS_supplyMaxEdge", 1500];
if !(_maxEdge isEqualType 0 && {_maxEdge > 0}) then { _maxEdge = 1500 };

private _spokeDist = missionNamespace getVariable ["A3A_CHAOS_supplySpokeDist", _maxEdge];
if !(_spokeDist isEqualType 0 && {_spokeDist > 0}) then { _spokeDist = _maxEdge };

private _maxLinks = missionNamespace getVariable ["A3A_CHAOS_supplyMaxLinks", 3];
if !(_maxLinks isEqualType 0 && {_maxLinks >= 1}) then { _maxLinks = 3 };
_maxLinks = round _maxLinks;

private _ratios = createHashMap;
private _allEdges = []; 
private _playerConnected = [];

private _spokeNames = (missionNamespace getVariable ["outposts", []]) + (missionNamespace getVariable ["seaports", []]);

// ---- Pass 1: candidate edges ---------------------------------------------
private _candidates = [];
private _candidateCount = 0;

{
    private _zones = _x;
    private _n = count _zones;
    private _sideCands = [];

    private _hubIdxs = [];
    private _spokeIdxs = [];
    {
        if ((_x # 3) in _spokeNames) then { _spokeIdxs pushBack _forEachIndex } else { _hubIdxs pushBack _forEachIndex };
    } forEach _zones;
    
    private _nh = count _hubIdxs;
    if (_nh > 0) then {
        for "_i" from 0 to (_nh - 2) do {
            private _a = _hubIdxs select _i;
            (_zones select _a) params ["_ax", "_ay", "_ar"];
            for "_j" from (_i + 1) to (_nh - 1) do {
                private _b = _hubIdxs select _j;
                (_zones select _b) params ["_bx", "_by", "_br"];
                private _dx = _bx - _ax;
                private _dy = _by - _ay;
                private _d2 = _dx * _dx + _dy * _dy;
                private _lim = ((_ar + _br) * _reachMult) min _maxEdge;
                if (_d2 <= _lim * _lim) then {
                    _sideCands pushBack [_a, _b, sqrt _d2, true]; 
                };
            };
        };
        
        // Force enemy carriers to strictly connect to their closest city and closest factory 
        // to prevent isolation from the network over wide ocean gaps.
        private _carrierIdx = _hubIdxs findIf { (_zones select _x) # 3 in ["NATO_carrier", "CSAT_carrier"] };
        if (_carrierIdx >= 0) then {
            private _c = _hubIdxs select _carrierIdx;
            private _cx = (_zones select _c) # 0;
            private _cy = (_zones select _c) # 1;
            
            private _bestCity = -1;
            private _bestCityD2 = 9999999999;
            private _bestFac = -1;
            private _bestFacD2 = 9999999999;
            
            private _cities = missionNamespace getVariable ["citiesX", []];
            private _factories = missionNamespace getVariable ["factories", []];
            
            {
                if (_x isEqualTo _c) then { continue };
                private _nName = (_zones select _x) # 3;
                private _d2 = ((_zones select _x) # 0 - _cx)^2 + ((_zones select _x) # 1 - _cy)^2;
                
                if (_nName in _cities && {_d2 < _bestCityD2}) then {
                    _bestCityD2 = _d2;
                    _bestCity = _x;
                };
                if (_nName in _factories && {_d2 < _bestFacD2}) then {
                    _bestFacD2 = _d2;
                    _bestFac = _x;
                };
            } forEach _hubIdxs;
            
            // Push manually without bounds limit. Sort order ensures standard processing.
            if (_bestCity >= 0) then {
                private _a = _c min _bestCity;
                private _b = _c max _bestCity;
                // Add it. Even if duplicate, graph structure merges cleanly or skips later
                _sideCands pushBack [_a, _b, sqrt _bestCityD2, true];
            };
            if (_bestFac >= 0 && _bestFac isNotEqualTo _bestCity) then {
                private _a = _c min _bestFac;
                private _b = _c max _bestFac;
                _sideCands pushBack [_a, _b, sqrt _bestFacD2, true];
            };
        };
    };
    
    {
        private _s = _x;
        (_zones select _s) params ["_sx", "_sy"];
        {
            private _h = _x;
            (_zones select _h) params ["_hx", "_hy"];
            private _dx = _hx - _sx;
            private _dy = _hy - _sy;
            private _d2 = _dx * _dx + _dy * _dy;
            if (_d2 <= _spokeDist * _spokeDist) then {
                 _sideCands pushBack [_s, _h, sqrt _d2, false];
            };
        } forEach _hubIdxs;
    } forEach _spokeIdxs;

    _candidates pushBack _sideCands;
    _candidateCount = _candidateCount + count _sideCands;
} forEach _sideZones;

private _denseSampling = true;
if (_candidateCount * _samplesMin > _sampleBudget) then {
    _denseSampling = false;
    Debug_2("computeSupplyGraph: %1 candidates over budget %2 - sampling at floor", _candidateCount, _sampleBudget);
};

// ---- Pass 2: corridor test, then BFS, per side --------------------------
private _samplesTaken = 0;

{
    private _sideIdx = _forEachIndex;
    private _side = _sideList select _sideIdx;
    private _zones = _sideZones select _sideIdx;
    private _sideCands = _candidates select _sideIdx;
    
    private _rgb = [_side] call _sideFallback;

    private _adj = [];
    { _adj pushBack [] } forEach _zones;
    
    private _survivorsHub = [];
    private _survivorsSpoke = [];

    {
        _x params ["_a", "_b", "_dist", "_isHubEdge"];
        (_zones select _a) params ["_ax", "_ay"];
        (_zones select _b) params ["_bx", "_by"];

        private _samples = _samplesMin;
        if (_denseSampling) then {
            _samples = (round (_dist / _sampleStep)) max _samplesMin min _samplesMax;
        };

        private _ok = true;
        for "_s" from 1 to _samples do {
            private _t = _s / (_samples + 1);
            private _sx = _ax + (_bx - _ax) * _t;
            private _sy = _ay + (_by - _ay) * _t;
            private _owner = ([_ctx, [_sx, _sy]] call A3A_fnc_influenceAt) # 0;
            _samplesTaken = _samplesTaken + 1;
            if (_owner != _sideIdx) exitWith { _ok = false };
        };

        if (_ok) then { 
            if (_isHubEdge) then { _survivorsHub pushBack [_a, _b, _dist] }
            else { _survivorsSpoke pushBack [_a, _b, _dist] };
        };
    } forEach _sideCands;

    // ---- Prune to the nearest _maxLinks per node FOR HUBS ONLY ------------
    private _incident = [];
    { _incident pushBack [] } forEach _zones;
    
    {
        _x params ["_a", "_b"];
        (_incident select _a) pushBack _forEachIndex;
        (_incident select _b) pushBack _forEachIndex;
    } forEach _survivorsHub;

    private _keep = [];
    { _keep pushBack false } forEach _survivorsHub;
    {
        private _edgeIdxs = _x;
        if (count _edgeIdxs <= _maxLinks) then {
            { _keep set [_x, true] } forEach _edgeIdxs;
        } else {
            private _remaining = +_edgeIdxs;
            for "_n" from 1 to _maxLinks do {
                if (_remaining isEqualTo []) exitWith {};
                private _bestPos = 0;
                private _bestLen = (_survivorsHub select (_remaining select 0)) # 2;
                {
                    private _len = (_survivorsHub select _x) # 2;
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
    } forEach _survivorsHub;

    if (_pruned > 0) then {
        Debug_3("computeSupplyGraph: side %1 kept %2 hub edges, pruned %3 to the link limit", _side, (count _survivorsHub) - _pruned, _pruned);
    };

    // ---- Root node (must be a hub) --------------------------------------
    private _rootIdx = -1;
    if (_side isEqualTo teamPlayer) then {
        _rootIdx = _zones findIf { (_x # 3) isEqualTo "Synd_HQ" };
    };
    if (_rootIdx < 0) then {
        _rootIdx = _zones findIf { (_x # 3) in ["NATO_carrier", "CSAT_carrier"] };
    };
    if (_rootIdx < 0) then {
        private _airports = missionNamespace getVariable ["airportsX", []];
        _rootIdx = _zones findIf { (_x # 3) in _airports };
    };
    if (_rootIdx < 0) then {
        _rootIdx = _zones findIf { !((_x # 3) in _spokeNames) };
    };
    if (_rootIdx < 0) then {
        private _bestR = -1;
        {
            if ((_x # 2) > _bestR) then { _bestR = _x # 2; _rootIdx = _forEachIndex };
        } forEach _zones;
    };

    // ---- Breadth-first walk from the root (building Backbone) -----------
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

    // ---- Attach Spokes to the Backbone ----------------------------------
    // Group surviving spoke edges by spoke node
    private _spokeEdgesMap = createHashMap;
    {
        _x params ["_s", "_h", "_dist"];
        if (_seen select _h) then {
            private _list = _spokeEdgesMap getOrDefault [_s, []];
            _list pushBack [_h, _dist];
            _spokeEdgesMap set [_s, _list];
        };
    } forEach _survivorsSpoke;

    // Pick the shortest valid connection for each spoke
    private _spokeKeys = keys _spokeEdgesMap;
    {
        private _s = _x;
        private _hubList = _spokeEdgesMap get _s;
        private _bestH = -1;
        private _bestDist = 1e9;
        {
            _x params ["_h", "_dist"];
            if (_dist < _bestDist) then { _bestDist = _dist; _bestH = _h };
        } forEach _hubList;
        
        if (_bestH >= 0) then {
            _seen set [_s, true];
            _connected pushBack ((_zones select _s) # 3);
            (_adj select _s) pushBack _bestH;
            (_adj select _bestH) pushBack _s;
        };
    } forEach _spokeKeys;

    private _owned = count _zones;
    private _ratio = if (_owned > 0) then { (count _connected) / _owned } else { 0 };
    _ratios set [_side, _ratio];
    
    // Collect edges for rendering
    private _sideRenderEdges = [];
    {
        private _a = _forEachIndex;
        {
            if (_x > _a) then {
                _sideRenderEdges pushBack [(_zones select _a) # 3, (_zones select _x) # 3];
            };
        } forEach _x;
    } forEach _adj;

    if (_side isEqualTo teamPlayer) then {
        _playerConnected = _connected;
    };
    
    _allEdges pushBack [_side, _rgb, _sideRenderEdges];

    Debug_3("computeSupplyGraph: side %1 - %2 of %3 zones connected", _side, count _connected, _owned);
} forEach _sideZones;

A3A_supplyRatios = _ratios;

A3A_supplyEdges = _allEdges;
publicVariable "A3A_supplyEdges";
A3A_supplyConnected = _playerConnected;
publicVariable "A3A_supplyConnected";

A3A_supplyGraphMs = (diag_tickTime - _tStart) * 1000;
Debug_3("computeSupplyGraph: %1 candidates, %2 samples, %3 ms", _candidateCount, _samplesTaken, A3A_supplyGraphMs);

true
