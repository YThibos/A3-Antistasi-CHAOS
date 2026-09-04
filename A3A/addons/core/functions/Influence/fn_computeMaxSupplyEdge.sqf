#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Computes the maximum edge length required for a Minimum Spanning Tree
    connecting all static hubs on the map, and assigns it to A3A_CHAOS_supplyMaxEdge.

Arguments: None
Return Value:
    <NUMBER> The computed maximum edge length in meters.

Scope: Server
Environment: Any
Public: No
*/

private _hubs = (missionNamespace getVariable ["citiesX", []]) + 
                (missionNamespace getVariable ["resourcesX", []]) +
                (missionNamespace getVariable ["factories", []]) +
                (missionNamespace getVariable ["airportsX", []]) +
                (missionNamespace getVariable ["seaports", []]);

if (count _hubs < 2) exitWith { 0 };

private _nodes = _hubs apply { getMarkerPos _x };
private _inTree = [_nodes # 0];
private _outTree = _nodes - [_nodes # 0];
private _maxEdge = 0;

while {count _outTree > 0} do {
    private _minDist = 999999;
    private _bestOut = objNull;
    {
        private _u = _x;
        {
            private _v = _x;
            private _d = _u distance2D _v;
            if (_d < _minDist) then { _minDist = _d; _bestOut = _v; };
        } forEach _outTree;
    } forEach _inTree;
    
    if (_minDist > _maxEdge) then { _maxEdge = _minDist };
    _inTree pushBack _bestOut;
    _outTree = _outTree - [_bestOut];
};

private _edgeLength = round (_maxEdge + 10); // +10m margin

missionNamespace setVariable ["A3A_CHAOS_supplyMaxEdge", _edgeLength, true];

private _msg = format ["Supply Network MST threshold computed and set: %1 m", _edgeLength];
if (hasInterface) then { systemChat _msg };
Info(_msg);

_edgeLength
