#include "..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    CHAOS site upgrade mission. Delivers the infrastructure that raises a rebel
    resource or factory a tier, which is what puts it on the supply graph at all
    (see A3A_fnc_siteTiers).

    Tier 1 - supply warehouse
        A shipping container spawns at HQ. Drive or sling it to the site, set it
        down inside the marker, then build the warehouse out of it with the
        normal builder action. The container is a builder box carrying a
        one-item catalogue, so the warehouse is placed through the RTS placer
        and can be ALIGNED before it is committed - it is a permanent structure
        and the player should get to decide how it sits.

        The container's build budget is exactly the warehouse's price, so
        fn_lockBuilderBox deletes the empty container on release. No cleanup
        needed and no leftover box at the site.

    Tier 2 - power generator
        A generator spawns at HQ instead. It is finished freight: set it down
        inside the marker and the site is Tier 2. Standing in for the heavy
        machinery the design wanted, since Arma has no excavator worth using.

    Both objects are logistics cargo and rope-attachable, so they load onto
    anything from an offroad up, exactly like the supply-delivery pallet.

    ---- No HQ distance limit ----------------------------------------------
    A3A_Tasks_fnc_LOG_SiteUpgrade_p deliberately does not filter targets by
    distanceMission; see its header. Timeouts here are correspondingly generous,
    because the far corner of the map is a legitimate target and a settled HQ
    must never be pushed to relocate just to keep upgrade missions coming.

Arguments:
    0: <ARRAY> [_marker, _targetTier] from the params function
    1: <ARRAY> Checkpoint data when resuming from a save (optional)

Return Value:
    <HASHMAP> The task state machine, per A3A_tasks_fnc_runTask's live contract.

Scope: Server
Environment: Scheduled (driven by runTask's loop)
Public: No
*/

#define UPGRADE_WAREHOUSE_PRICE 1500

private _fnc_createCargo = {
    params ["_pos", "_targetTier"];
    private _class = ["Land_Cargo10_blue_F", "Land_PowerGenerator_F"] select (_targetTier >= 2);
    private _obj = _class createVehicle _pos;
    _obj enableRopeAttach true;

    // initObject registers it as a rebel-placed, persisted object and - for the
    // container - adds the builder action, because the class carries the "build"
    // flag in fn_initUtilityItems.
    [_obj] call A3A_fnc_initObject;

    // AFTER initObject, which sets A3A_itemPrice from the catalogue (-1, since
    // neither object is purchasable). fn_lockBuilderBox turns this into the
    // build budget, so it has to be the warehouse's exact price.
    if (_targetTier < 2) then {
        _obj setVariable ["A3A_itemPrice", UPGRADE_WAREHOUSE_PRICE, true];
    };

    [_obj, teamPlayer] call A3A_fnc_AIVEHinit;
    _task set ["_cargo", _obj];
};

private _fnc_createTask = {
    private _nameDest = [_this get "_marker"] call A3A_fnc_localizar;
    private _displayTime = [((_this get "_endTime") - time) / 60] call FUNC(minutesFromNow);
    private _targetTier = _this get "_targetTier";

    private _taskName = localize "STR_A3A_Tasks_LOG_SiteUpgrade_title";
    private _descKey = ["STR_A3A_Tasks_LOG_SiteUpgrade_description_t1", "STR_A3A_Tasks_LOG_SiteUpgrade_description_t2"] select (_targetTier >= 2);
    private _taskDesc = format [localize _descKey, _nameDest, _displayTime];
    private _taskPos = markerPos (_this get "_marker");
    private _notify = isNil {_this get "checkpoint"};
    private _taskId = call FUNC(genTaskUID);
    [true, _taskId, [_taskDesc, _taskName], _taskPos, false, -1, _notify, "Repair", true] call BIS_fnc_taskCreate;
    _this set ["_taskId", _taskId];
};

params ["_params", "_checkpoint"];

private _task = createHashMap;

if (isNil "_checkpoint") then {
    _params params ["_marker", "_targetTier"];

    private _hqPos = getMarkerPos respawnTeamPlayer;
    private _spawnPos = _hqPos findEmptyPosition [1, 75, "C_Van_01_box_F"];
    if (_spawnPos isEqualTo []) then { _spawnPos = _hqPos getPos [75 * sqrt random 1, random 360] };

    _task set ["_marker", _marker];
    _task set ["_targetTier", _targetTier];
    [_spawnPos, _targetTier] call _fnc_createCargo;

    // Generous, and scaled by how far the site actually is: this mission has no
    // distance cutoff, so the clock has to survive a cross-map haul.
    private _dist = (markerPos _marker) distance2D _hqPos;
    _task set ["_endTime", time + 60 * (30 + (_dist / 100))];
    _task call _fnc_createTask;
}
else {
    _params params ["_marker", "_targetTier", "_cargoPos", "_remTime"];

    _task set ["_marker", _marker];
    _task set ["_targetTier", _targetTier];
    [_cargoPos, _targetTier] call _fnc_createCargo;
    _task set ["_endTime", time + _remTime];
    _task call _fnc_createTask;
};

A3A_activeTasks pushBack "SITE";

_task set ["checkpoint", "c_started"];
_task set ["state", "s_deliver"];
_task set ["interval", 5];
_task set ["_hintTitle", localize "STR_A3A_Tasks_LOG_SiteUpgrade_title"];

_task set ["c_started", {
    [_this get "_marker", _this get "_targetTier", getPosATL (_this get "_cargo"), (_this get "_endTime") - time];
}];

/////////////////////
// State functions //
/////////////////////

// Set down inside the marker, under nothing's hook or rope.
_task set ["_fnc_deliveredCondition", {
    private _cargo = _this get "_cargo";
    private _marker = _this get "_marker";
    if (isNull _cargo || {!alive _cargo}) exitWith { false };
    if (!isNull attachedTo _cargo || {!isNull ropeAttachedTo _cargo}) exitWith { false };
    private _radius = [_marker] call A3A_fnc_garrisonVehicleRadius;
    if (_radius <= 0) then { _radius = 100 };
    (_cargo distance2D markerPos _marker) <= _radius
}];

_task set ["s_deliver", {
    if ((_this get "_endTime") < time) exitWith { _this set ["state", "s_failed"]; false };

    private _cargo = _this get "_cargo";
    if (isNull _cargo || {!alive _cargo}) exitWith {
        // Destroyed in transit. Nothing to recover, so the run is lost.
        _this set ["state", "s_failed"]; false
    };

    if !(_this call (_this get "_fnc_deliveredCondition")) exitWith { false };

    // Tier 2 is finished freight: setting it down IS the upgrade.
    if ((_this get "_targetTier") >= 2) exitWith {
        call A3A_fnc_siteTiers;
        [] call A3A_fnc_refreshSupplyGraph;
        _this set ["state", "s_succeeded"]; false
    };

    [_this get "_hintTitle", localize "STR_A3A_Tasks_LOG_SiteUpgrade_nowBuild", getPosATL _cargo, 100] call FUNC(hintNear);
    _this set ["state", "s_build"]; false
}];

_task set ["s_build", {
    if ((_this get "_endTime") < time) exitWith { _this set ["state", "s_failed"]; false };

    private _marker = _this get "_marker";

    // The warehouse is what completes this, not the container - which
    // fn_lockBuilderBox deletes the moment its budget is spent. So the tier is
    // the only thing worth testing, and fn_buildingComplete has already
    // recomputed it by the time the structure exists.
    private _tierData = [_marker] call A3A_fnc_siteTier;
    if ((_tierData # 0) >= 1) exitWith { _this set ["state", "s_succeeded"]; false };

    // Container hauled back out of the marker before the warehouse went up.
    private _cargo = _this get "_cargo";
    if (!isNull _cargo && {alive _cargo} && {!(_this call (_this get "_fnc_deliveredCondition"))}) exitWith {
        _this set ["state", "s_deliver"]; false
    };

    false
}];

_task set ["s_succeeded", {
    private _marker = _this get "_marker";
    private _targetTier = _this get "_targetTier";
    private _bonus = [1, 2] select (_targetTier >= 2);

    [_this get "_hintTitle", localize "STR_A3A_Tasks_LOG_SiteUpgrade_done", markerPos _marker, 300] call FUNC(hintNear);

    [20 * _bonus, false, markerPos _marker, 300] call FUNC(rewardPlayers);
    [0, 150 * _bonus] remoteExec ["A3A_fnc_resourcesFIA", 2];

    [_this get "_taskId", "SUCCEEDED"] call BIS_fnc_taskSetState;
    _this set ["state", "s_cleanup"]; false;
}];

_task set ["s_failed", {
    [_this get "_hintTitle", localize "STR_A3A_Tasks_LOG_SiteUpgrade_failed", markerPos (_this get "_marker"), 300] call FUNC(hintNear);
    [-10, theBoss] call A3A_fnc_playerScoreAdd;
    [_this get "_taskId", "FAILED"] call BIS_fnc_taskSetState;
    _this set ["state", "s_cleanup"]; false;
}];

_task set ["s_cleanup", {
    // The container deletes itself once its budget is spent, and a delivered
    // generator is the upgrade, so neither is cleaned up here. Only an
    // undelivered container left lying at HQ on a failure is worth removing.
    private _cargo = _this get "_cargo";
    if (!isNull _cargo && {(_this get "_targetTier") < 2} && {!(_this call (_this get "_fnc_deliveredCondition"))}) then {
        deleteVehicle _cargo;
    };

    [1200, _this get "_taskId"] spawn {
        params ["_delay", "_taskId"];
        sleep _delay;
        A3A_activeTasks deleteAt (A3A_activeTasks find "SITE");
        publicVariable "A3A_activeTasks";
        [_taskId, true, true] call BIS_fnc_deleteTask;
    };

    true;
}];

_task
