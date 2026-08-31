#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Debounced entry point for rebuilding the supply graph.

    Territory events arrive in bursts - taking an outpost fires markerChange
    and usually moves a garrison and a control site with it - and the graph is
    expensive enough that rebuilding once per event in a burst would be pure
    waste. So a request arms a CBA timer and any further request inside that
    window is folded into the pending one. The graph is at most _debounce
    seconds stale, which is nothing against a 600-second income tick.

    Pass _force to rebuild immediately and synchronously: used by the resource
    tick, which wants a graph that reflects the world right now because it is
    about to spend it.

Arguments:
    0: <BOOL> Rebuild now instead of arming the debounce. (optional, default false)

Return Value:
    <BOOL> true when a rebuild actually ran during this call.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_computeSupplyGraph, CBA_fnc_waitAndExecute
*/

params [["_force", false, [false]]];

if (!isServer) exitWith { false };

if (_force) exitWith {
    A3A_supplyGraphPending = false;
    call A3A_fnc_computeSupplyGraph
};

// Already armed: this request is folded into the pending rebuild.
if (missionNamespace getVariable ["A3A_supplyGraphPending", false]) exitWith { false };

A3A_supplyGraphPending = true;
private _debounce = 5;

[{
    A3A_supplyGraphPending = false;
    call A3A_fnc_computeSupplyGraph;
}, [], _debounce] call CBA_fnc_waitAndExecute;

false
