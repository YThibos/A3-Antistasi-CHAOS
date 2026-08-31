#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    How much of its normal resource rate a side is actually getting, given how
    much of its territory is still connected to its own root node.

        multiplier = _floor + (1 - _floor) * (connected / owned)

    ---- Why there is a floor -----------------------------------------------
    A fully severed faction at a zero rate stops defending and stops
    counterattacking, and a faction that cannot punch back is a dead endgame:
    the player would be optimising the map toward nothing happening. Half rate
    is crippled but still dangerous, which is the behaviour worth having.

    ---- Where it bites -----------------------------------------------------
    fn_aggressionUpdateLoop feeds A3A_resourcesDefence* and A3A_resourcesAttack*
    from these rates, and caps the defence stockpile at _resRateDef * 100. So
    cutting an enemy's lines does not merely slow their income, it lowers the
    ceiling on their banked defensive reserve - their surplus is stranded.
    Cut, wait a few ticks, then attack is a real strategy that falls out of
    this one number.

    The multiplier stacks multiplicatively with the existing no-airport penalty
    in that loop, which is the same kind of territorial modifier and the
    precedent this follows.

Arguments:
    0: <SIDE> The side to look up.

Return Value:
    <NUMBER> Multiplier in [_floor, 1]. Exactly 1 when no graph has been built
             yet or the side holds nothing, so this can never be the reason a
             faction mysteriously stops functioning.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    A3A_supplyRatios (server-side hashmap, written by A3A_fnc_computeSupplyGraph)
*/

params [["_side", sideUnknown, [sideUnknown]]];

private _ratios = missionNamespace getVariable ["A3A_supplyRatios", createHashMap];
if !(_ratios isEqualType createHashMap) exitWith { 1 };

private _ratio = _ratios getOrDefault [_side, -1];
if !(_ratio isEqualType 0) exitWith { 1 };
if (_ratio < 0) exitWith { 1 };            // side not in the graph at all

private _floor = missionNamespace getVariable ["A3A_CHAOS_supplyRateFloor", 0.5];
if !(_floor isEqualType 0 && {_floor >= 0} && {_floor <= 1}) then { _floor = 0.5 };

_floor + (1 - _floor) * (_ratio max 0 min 1)
