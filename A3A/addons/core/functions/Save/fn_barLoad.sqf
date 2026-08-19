#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Restore BAR (Build And Resources) state saved by fn_barSave.sqf.
    Called from fn_loadServer.sqf when A3A_hasBAR is true.

    1.  Recreates BAR-placed structures and populates A3A_barBuiltObjects so
        the Persistency_fnc_saveObject / Persistency_fnc_removeObject hooks
        continue to track them.  The BAR demolish ACE action is re-attached
        with a zero build cost (original cost is not stored on save).

    2.  Sets up an EntityCreated mission event handler that patches
        BuildAndRessources_ressources and BuildAndRessources_depotStocks on
        BAR crate / depot objects as the garrison spawner creates them.
        The EH removes itself once all pending entries have been matched.

Arguments:
    0: <ARRAY> A3A_barSaveData = [_builtData, _crateResources, _depotResources]
        _builtData     : ARRAY of [className, posWorld, vectorDir, vectorUp]
        _crateResources: ARRAY of [posWorld, [Concrete,Wood,Sand,Metal]]
        _depotResources: ARRAY of [posWorld, [Concrete,Wood,Sand,Metal]]

Return Value:
    <nil>

Scope: Server
Environment: Unscheduled (called from fn_loadServer)
Public: No
*/
params [["_saveData", [], [[]]]];

if (!isServer) exitWith {};

_saveData params [
    ["_builtData",      [], [[]]],
    ["_crateResources", [], [[]]],
    ["_depotResources", [], [[]]]
];

// ---- 1. Recreate BAR placed structures --------------------------------------
A3A_barBuiltObjects = [];
{
    _x params ["_class", "_posW", "_vecDir", "_vecUp"];
    private _obj = createVehicle [_class, [0,0,0], [], 0, "CAN_COLLIDE"];
    _obj setPosWorld _posW;
    _obj setVectorDirAndUp [_vecDir, _vecUp];
    A3A_barBuiltObjects pushBack _obj;

    // Re-attach the BAR demolish ACE action.
    // Build cost stored as [0,0,0,0] because the original cost is not persisted.
    // The player will be able to demolish but will not receive a resource refund.
    [_obj, 30, _class, [], [0,0,0,0]] remoteExecCall ["BuildAndRessources_fnc_deleteObject", 0, true];
} forEach _builtData;

Info_1("barLoad: recreated %1 BAR structure(s)", count _builtData);

// ---- 2. Build position-keyed lookup maps ------------------------------------
// Key format: "<x*10>_<y*10>_<z*10>"  absorbs floating-point drift across save/load.
private _crateMap = createHashMap;
{
    private _pos = _x#0;
    private _res = _x#1;
    // Guard: accept only the 4-element array written by the new barSave.
    // (Old saves stored a scalar; skip those to avoid setting a broken variable.)
    if !(_res isEqualType [] && { count _res == 4 }) then { continue };
    private _key = format ["%1_%2_%3",
        round (_pos#0 * 10), round (_pos#1 * 10), round (_pos#2 * 10)];
    _crateMap set [_key, _res];
} forEach _crateResources;

private _depotMap = createHashMap;
{
    private _pos = _x#0;
    private _stocks = _x#1;
    if !(_stocks isEqualType [] && { count _stocks == 4 }) then { continue };
    private _key = format ["%1_%2_%3",
        round (_pos#0 * 10), round (_pos#1 * 10), round (_pos#2 * 10)];
    _depotMap set [_key, _stocks];
} forEach _depotResources;

if (_crateMap isEqualTo createHashMap && { _depotMap isEqualTo createHashMap }) exitWith {
    Info("barLoad: no crate/depot resource data to restore");
};

A3A_barCrateMap = _crateMap;
A3A_barDepotMap = _depotMap;

Info_2("barLoad: waiting to restore %1 crate(s) and %2 depot(s)",
    count A3A_barCrateMap, count A3A_barDepotMap);

// ---- 3. EntityCreated EH — patch resources as objects are spawned -----------
A3A_barLoadEhID = addMissionEventHandler ["EntityCreated", {
    params ["_entity"];

    private _typeOf  = typeOf _entity;
    private _isCrate = _typeOf in ["RessourceCrate_Concrete", "RessourceCrate_Wood",
                                    "RessourceCrate_Sand",    "RessourceCrate_Metal"];
    private _isDepot = _typeOf isEqualTo "RessourceDepot";

    if (!_isCrate && !_isDepot) exitWith {};

    private _pos = getPosWorld _entity;
    private _key = format ["%1_%2_%3",
        round (_pos#0 * 10), round (_pos#1 * 10), round (_pos#2 * 10)];

    if (_isCrate) then {
        private _saved = A3A_barCrateMap getOrDefault [_key, []];
        if !(_saved isEqualTo []) then {
            _entity setVariable ["BuildAndRessources_ressources", _saved, true];
            A3A_barCrateMap deleteAt _key;
            Debug_2("barLoad: restored crate resources %1 at %2", _saved, _pos);
        };
    };

    if (_isDepot) then {
        private _saved = A3A_barDepotMap getOrDefault [_key, []];
        if !(_saved isEqualTo []) then {
            _entity setVariable ["BuildAndRessources_depotStocks", _saved, true];
            A3A_barDepotMap deleteAt _key;
            Debug_2("barLoad: restored depot stocks %1 at %2", _saved, _pos);
        };
    };

    if (A3A_barCrateMap isEqualTo createHashMap && { A3A_barDepotMap isEqualTo createHashMap }) then {
        removeMissionEventHandler ["EntityCreated", A3A_barLoadEhID];
        Info("barLoad: all BAR crate/depot resources restored; EH removed");
        A3A_barCrateMap = nil;
        A3A_barDepotMap = nil;
        A3A_barLoadEhID = nil;
    };
}];
