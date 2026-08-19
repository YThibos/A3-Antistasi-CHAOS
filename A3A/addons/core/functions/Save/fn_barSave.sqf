#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Collect BAR (Build And Resources) persistent state for the Antistasi save
    file.  Called from fn_saveLoop.sqf when A3A_hasBAR is true.

    Three kinds of state are saved:

    1. BAR-placed structures (dragon's teeth, fortifications, …) tracked in
       A3A_barBuiltObjects by the Persistency_fnc_saveObject /
       Persistency_fnc_removeObject hooks (see functions\BAR\).

    2. Current resource amounts in each live BAR crate, keyed by world
       position.  The garrison recreates crate objects from class + position
       but does not preserve mod-specific variables, so each crate's level
       would otherwise reset to BAR's default (full) on reload.

    3. Current resource amounts in each live BAR depot, keyed by world
       position.  Depots are utility items that survive reload, but their
       BuildAndRessources_depotStocks variable is not saved by the garrison.

    Real BAR variable names (verified against BuildAndRessources.pbo source):
        Crate resource array : "BuildAndRessources_ressources"  [Concrete,Wood,Sand,Metal]
        Depot stock array    : "BuildAndRessources_depotStocks" [Concrete,Wood,Sand,Metal]

Arguments:
    none

Return Value:
    <ARRAY> [_builtData, _crateResources, _depotResources]
        _builtData     : ARRAY of [className, posWorld, vectorDir, vectorUp]
        _crateResources: ARRAY of [posWorld, [Concrete,Wood,Sand,Metal]]
        _depotResources: ARRAY of [posWorld, [Concrete,Wood,Sand,Metal]]

Scope: Server
Environment: Unscheduled (called from fn_saveLoop)
Public: No
*/
if (!isServer) exitWith { [[], [], []] };

// ---- 1. BAR placed structures -----------------------------------------------
if (isNil "A3A_barBuiltObjects") then { A3A_barBuiltObjects = [] };
A3A_barBuiltObjects = A3A_barBuiltObjects select { !isNull _x };   // drop demolished entries

private _builtData = A3A_barBuiltObjects apply {
    [typeOf _x, getPosWorld _x, vectorDir _x, vectorUp _x]
};

Info_1("barSave: %1 BAR structure(s)", count _builtData);

// ---- 2. BAR crate resource snapshot -----------------------------------------
private _crateClasses = ["RessourceCrate_Concrete", "RessourceCrate_Wood",
                          "RessourceCrate_Sand",     "RessourceCrate_Metal"];
private _crateResources = [];
{
    private _crate = _x;
    if (!alive _crate) then { continue };
    private _res = _crate getVariable ["BuildAndRessources_ressources", []];
    // Empty array means BAR has not touched this crate yet; skip it and let BAR
    // initialise it to its own default (capacity) on reload.
    if (_res isEqualTo []) then { continue };
    _crateResources pushBack [getPosWorld _crate, _res];
} forEach (
    allMissionObjects "RessourceCrate_Concrete"
    + allMissionObjects "RessourceCrate_Wood"
    + allMissionObjects "RessourceCrate_Sand"
    + allMissionObjects "RessourceCrate_Metal"
);

Info_1("barSave: %1 BAR crate(s)", count _crateResources);

// ---- 3. BAR depot resource snapshot -----------------------------------------
private _depotResources = [];
{
    private _depot = _x;
    if (!alive _depot) then { continue };
    private _stocks = _depot getVariable ["BuildAndRessources_depotStocks", []];
    if (_stocks isEqualTo []) then { continue };    // not yet initialised by BAR
    _depotResources pushBack [getPosWorld _depot, _stocks];
} forEach (allMissionObjects "RessourceDepot");

Info_1("barSave: %1 BAR depot(s)", count _depotResources);

[_builtData, _crateResources, _depotResources]
