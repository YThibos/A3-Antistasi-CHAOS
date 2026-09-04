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
        fn_lockBuilderBox usually deletes the empty container when the player
        releases it. That is a convenience, not a guarantee - s_cleanup deletes
        the container itself so a finished mission can never leave one standing.

    Tier 2 - power generator
        A generator spawns at HQ instead. It is finished freight: set it down
        inside the marker and the site is Tier 2. Standing in for the heavy
        machinery the design wanted, since Arma has no excavator worth using.
        On delivery it is filed into the site's garrison record, which is both
        what makes it persist and what A3A_fnc_siteTiers reads.

    Both objects are logistics cargo and rope-attachable, so they load onto
    anything from an offroad up, exactly like the supply-delivery pallet.

    ---- Upgrading is not the same as being connected ----------------------
    Completing this mission raises the site's tier, and tier is what makes a
    resource or factory ELIGIBLE to be a hub in A3A_fnc_computeSupplyGraph. It
    does not connect it. The graph still has to find a corridor to it that is
    inside the edge cap and not interdicted, and the params function below
    deliberately offers sites at any distance from HQ, so "upgraded but not on
    the network" is a normal, legitimate outcome rather than a failure. The
    completion message is therefore chosen from A3A_supplyConnected at the
    moment it fires, not assumed.

    ---- No HQ distance limit ----------------------------------------------
    A3A_Tasks_fnc_ECON_SiteUpgrade_p deliberately does not filter targets by
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

    private _taskName = localize "STR_A3A_Tasks_ECON_SiteUpgrade_title";
    private _descKey = ["STR_A3A_Tasks_ECON_SiteUpgrade_description_t1", "STR_A3A_Tasks_ECON_SiteUpgrade_description_t2"] select (_targetTier >= 2);
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

// Category key, matching Tasks.hpp. This is what fn_requestTask throttles on:
// while it is present, no other ECON mission can be requested, and the cleanup
// state removes it again.
A3A_activeTasks pushBack "ECON";

_task set ["checkpoint", "c_started"];
_task set ["state", "s_deliver"];
_task set ["interval", 5];
_task set ["_hintTitle", localize "STR_A3A_Tasks_ECON_SiteUpgrade_title"];

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
    // Floored, because resource and factory markers are routinely smaller than
    // the site they name. Kept well under the 150 m claim radius that
    // fn_buildingComplete and fn_siteTiers use, so a container accepted here
    // can still put its warehouse 50 m further out and have it counted.
    private _radius = ([_marker] call A3A_fnc_garrisonVehicleRadius) max 75;
    (_cargo distance2D markerPos _marker) <= _radius
}];

_task set ["s_deliver", {
    if ((_this get "_endTime") < time) exitWith { _this set ["state", "s_failed"]; false };

    private _cargo = _this get "_cargo";
    private _marker = _this get "_marker";
    if (isNull _cargo || {!alive _cargo}) exitWith {
        // Destroyed in transit. Nothing to recover, so the run is lost.
        _this set ["state", "s_failed"]; false
    };

    if !(_this call (_this get "_fnc_deliveredCondition")) exitWith { false };

    // Tier 2 is finished freight: setting it down IS the upgrade.
    if ((_this get "_targetTier") >= 2) exitWith {
        // File it into the site's garrison explicitly. The generator carries the
        // "save" flag, so fn_rebelVehPlacedWorker would normally garrison it -
        // but that path routes through fn_getMarkerForPos, which returns "" for
        // anything set down outside the marker's own outline and silently drops
        // the object. Naming the marker here is the whole point: the mission
        // already knows which site this is, and the garrison record is what
        // A3A_fnc_siteTiers reads and what the save carries.
        [_marker, _cargo] call A3A_fnc_garrisonServer_addVehicle;
        call A3A_fnc_siteTiers;
        [] call A3A_fnc_refreshSupplyGraph;
        _this set ["state", "s_succeeded"]; false
    };

    [_this get "_hintTitle", localize "STR_A3A_Tasks_ECON_SiteUpgrade_nowBuild", getPosATL _cargo, 100] call FUNC(hintNear);
    _this set ["state", "s_build"]; false
}];

_task set ["s_build", {
    if ((_this get "_endTime") < time) exitWith { _this set ["state", "s_failed"]; false };

    private _marker = _this get "_marker";

    // The warehouse is what completes this, not the container - which
    // fn_lockBuilderBox deletes the moment its budget is spent. So the tier is
    // the only thing worth testing, and fn_buildingComplete has already
    // recomputed it by the time the structure exists. Recomputed here anyway:
    // it is one pass over a handful of markers every 5 s, and it means the
    // mission never depends on someone else having remembered to refresh.
    call A3A_fnc_siteTiers;
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

    // ---- Say what is actually true ------------------------------------
    // Reaching a tier makes the site a CANDIDATE hub. It does not put it on the
    // network: A3A_fnc_computeSupplyGraph still has to find it a corridor that
    // survives the distance cap and is not interdicted, and this mission has no
    // distance cutoff at all (see the params function), so a site upgraded on
    // the far side of the map can legitimately end up upgraded and unlinked.
    //
    // The states above call A3A_fnc_refreshSupplyGraph WITHOUT _force, which
    // only arms the 5 s debounce, so A3A_supplyConnected here would still be the
    // pre-upgrade graph. Force it before reading it, or the answer is one
    // rebuild out of date whichever way it goes.
    call A3A_fnc_siteTiers;
    [true] call A3A_fnc_refreshSupplyGraph;

    private _tier = ([_marker] call A3A_fnc_siteTier) # 0;
    private _connected = _marker in (missionNamespace getVariable ["A3A_supplyConnected", []]);
    private _nameDest = [_marker] call A3A_fnc_localizar;
    private _doneKey = ["STR_A3A_Tasks_ECON_SiteUpgrade_doneUnlinked", "STR_A3A_Tasks_ECON_SiteUpgrade_done"] select _connected;
    private _doneText = format [localize _doneKey, _nameDest, _tier];

    [_this get "_hintTitle", _doneText, markerPos _marker, 300] call FUNC(hintNear);

    // The description is what the player reads in the task list after the
    // notification has gone, and it still said the site was not connected to
    // anything. Rewrite it to the outcome, the way fn_cityBattle does on every
    // state change.
    [_this get "_taskId", [_doneText, _this get "_hintTitle", ""]] call BIS_fnc_taskSetDescription;

    [20 * _bonus, false, markerPos _marker, 300] call FUNC(rewardPlayers);
    [0, 150 * _bonus] remoteExec ["A3A_fnc_resourcesFIA", 2];

    [_this get "_taskId", "SUCCEEDED"] call BIS_fnc_taskSetState;
    _this set ["_succeeded", true];
    _this set ["state", "s_cleanup"]; false;
}];

_task set ["s_failed", {
    private _failText = localize "STR_A3A_Tasks_ECON_SiteUpgrade_failed";
    [_this get "_hintTitle", _failText, markerPos (_this get "_marker"), 300] call FUNC(hintNear);
    [_this get "_taskId", [_failText, _this get "_hintTitle", ""]] call BIS_fnc_taskSetDescription;
    [-10, theBoss] call A3A_fnc_playerScoreAdd;
    [_this get "_taskId", "FAILED"] call BIS_fnc_taskSetState;
    _this set ["state", "s_cleanup"]; false;
}];

_task set ["s_cleanup", {
    // Dispose of the delivery object explicitly. The Tier 1 container used to be
    // left to fn_lockBuilderBox, which deletes a builder box released with no
    // budget left - but nothing guarantees the player ever releases it cleanly.
    // Build the warehouse and disconnect, or hand the box off, and a blue
    // container sits at the site for the rest of the campaign. The mission
    // delivered it, so the mission removes it.
    //
    // The Tier 2 generator is the opposite: on success it IS the upgrade and
    // must stay. It is only removed when the run did not succeed.
    private _cargo = _this get "_cargo";
    private _keepCargo = (_this get "_targetTier") >= 2 && { _this getOrDefault ["_succeeded", false] };
    if (!isNull _cargo && {!_keepCargo}) then {
        // remVehicle deletes on its own if the object was never garrisoned, so
        // this covers both the loose container and a generator that got filed
        // into the site before the run timed out.
        [_cargo, true] call A3A_fnc_garrisonServer_remVehicle;
    };

    [1200, _this get "_taskId"] spawn {
        params ["_delay", "_taskId"];
        sleep _delay;
        A3A_activeTasks deleteAt (A3A_activeTasks find "ECON");
        publicVariable "A3A_activeTasks";
        [_taskId, true, true] call BIS_fnc_deleteTask;
    };

    true;
}];

_task
