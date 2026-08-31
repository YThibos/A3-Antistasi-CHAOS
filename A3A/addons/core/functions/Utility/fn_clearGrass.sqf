/*
 * File: fn_clearGrass.sqf
 * Function: A3A_fnc_clearGrass
 * Description:
 *    Clears procedural grass clutter in a 3-meter radius around the unit using an entrenching tool.
 *
 * Parameters:
 *    0: <OBJECT> The player unit clearing the grass (default: player)
 *
 * Returns:
 *    None
 *
 * Example:
 *    [player] call A3A_fnc_clearGrass;
 */

#include "..\..\script_component.hpp"

params [["_player", player, [objNull]]];

if (isNull _player || {!alive _player} || {!local _player}) exitWith {};

if !([_player, "ACE_EntrenchingTool"] call BIS_fnc_hasItem) exitWith {
    [localize "STR_A3A_actions_clear_grass", localize "STR_A3A_actions_clear_grass_no_tool"] call A3A_fnc_customHint;
};

if (!isNull objectParent _player || {surfaceIsWater (getPos _player)} || {((getPosATL _player) select 2) >= 1}) exitWith {};

private _startPos = getPosATL _player;

// Determine animation based on stance
private _anim = if (stance _player == "PRONE") then {
    "AinvPpneMstpSnonWnonDnon_medic4"
} else {
    "AinvPknlMstpSnonWnonDnon_medic4"
};

// Play digging sound
if (isClass (configFile >> "CfgPatches" >> "ace_trenches")) then {
    playSound3D ["z\ace\addons\trenches\sounds\dig.wss", _player, false, getPosASL _player, 2, 1, 20];
} else {
    playSound3D ["A3\Sounds_F\characters\human-sfx\Other\dirty_metal_01.wss", _player, false, getPosASL _player, 1.5, 1, 15];
};

[_player, _anim] call ace_common_fnc_doAnimation;

private _onFinish = {
    params ["_args"];
    _args params ["_player", "_startPos"];

    if (isNull _player || {!alive _player}) exitWith {};

    private _pos = getPosATL _player;
    private _cutter = createVehicle ["Land_ClutterCutter_medium_F", _pos, [], 0, "CAN_COLLIDE"];
    _cutter setPosATL [_pos#0, _pos#1, 0];
    _cutter enableSimulationGlobal false;
    _cutter allowDamage false;

    [localize "STR_A3A_actions_clear_grass", localize "STR_A3A_actions_clear_grass_success"] call A3A_fnc_customHint;
};

private _onFailure = {
    params ["_args"];
    _args params ["_player"];
    if (!isNull _player && {alive _player}) then {
        [_player, ""] call ace_common_fnc_doAnimation;
    };
};

private _condition = {
    params ["_args"];
    _args params ["_player", "_startPos"];
    alive _player &&
    {isNull objectParent _player} &&
    {!(_player getVariable ["ACE_isUnconscious", false])} &&
    {_player distance _startPos < 0.5} &&
    {[_player, "ACE_EntrenchingTool"] call BIS_fnc_hasItem}
};

[
    2,
    [_player, _startPos],
    _onFinish,
    _onFailure,
    localize "STR_A3A_actions_clear_grass_progress",
    _condition,
    ["isNotInside", "isNotSwimming"]
] call ace_common_fnc_progressBar;
