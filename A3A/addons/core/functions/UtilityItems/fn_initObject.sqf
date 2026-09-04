/*
Author: Killerswin2
    Function to initialize buyable items

Arguments:
    0.<Object> Object to initialize. Should be present in A3A_utilityItemHM

Return Value:
    <nil>

Scope: Anywhere
Environment: Unscheduled
Public: No
Dependencies:

Example:
    [_object] call A3A_fnc_initObject;
*/
#include "..\..\script_component.hpp"

params [["_object", objNull, [objNull]]];

if (isNull _object) exitWith { Error("Non-existent object passed") };
if !(typeof _object in A3A_utilityItemHM) exitWith { Error_1("initObject used on object type %1", typeof _object) };
if (!isNil {_object getVariable "A3A_canGarage"}) exitWith { Error_1("Object type %1 already initialized", typeof _object) };

(A3A_utilityItemHM get typeof _object) params ["", "_price", "", "", "_flags"];

// clear inventory. May or may not be done elsewhere
if !("noclear" in _flags) then {
    clearMagazineCargoGlobal _object;
    clearWeaponCargoGlobal _object;
    clearItemCargoGlobal _object;
    clearBackpackCargoGlobal _object;
};

// Double loot crate max load if we're running with no unlocks
if ("loot" in _flags and minWeaps == -1) then {
    [_object, (maxLoad _object) * 2] remoteExecCall ["setMaxLoad", 2];      // setMaxLoad is server-execution
};

_object setVariable ["A3A_canGarage", true, true];
_object setVariable ["A3A_itemPrice", _price, true];

// CHAOS: BAR crates are bought empty. BAR spawns its crates carrying stock, and
// the price now covers the container only, so the contents are zeroed here.
// Public, because every machine reads the crate's own resource array to decide
// what it can build. A crate restored by fn_barLoad never comes through this
// path - it already carries its saved contents and must keep them.
if ("barempty" in _flags) then {
    _object setVariable ["BuildAndRessources_ressources", [0,0,0,0], true];
};

// CHAOS: a freshly created BAR depot starts with a tenth of its capacity in each
// material rather than bone empty. The depot costs 3000 credits and is gated
// behind the Construction Yard; arriving with nothing in it means the player
// pays for the gate and then waits several income ticks before it does anything.
// fn_factoryDepotTick tops it up from there and enforces the same cap.
//
// Reached from both depot paths: fn_buildingComplete calls initObject on a
// newly built depot, and fn_AIVEHinit calls it on one the garrison respawns.
// Hence the isNil guard - only a depot whose stocks have never been set gets
// seeded. On a campaign reload fn_barLoad's EntityCreated handler has already
// written the saved stocks by the time the garrison spawner reaches
// fn_AIVEHinit, and an unguarded seed would overwrite them with cap/10.
if (typeOf _object isEqualTo "RessourceDepot"
    && {isNil {_object getVariable "BuildAndRessources_depotStocks"}}) then {
    private _seed = floor ((missionNamespace getVariable ["A3A_CHAOS_barDepotCap", 3000]) / 10);
    _object setVariable ["BuildAndRessources_depotStocks", [_seed, _seed, _seed, _seed], true];
};

if ("save" in _flags) then {
    [_object] remoteExec ["A3A_fnc_rebelVehPlacedWorker", 2];
    [_object] remoteExecCall ["A3A_fnc_addVehAttachDetachEH", 2];
};

// Let logistics do its own JIPing for the moment
// Assumption that the object isn't loaded into anything?
if ([typeOf _object] call A3A_Logistics_fnc_isLoadable) then {[_object] call A3A_Logistics_fnc_addLoadAction};

// All other object actions, hopefully
private _jipKey = "A3A_initObject_" + ((str _object splitString ":") joinString "");
[_object, _jipKey] remoteExecCall ["A3A_fnc_initObjectRemote", 0, _jipKey]; 
