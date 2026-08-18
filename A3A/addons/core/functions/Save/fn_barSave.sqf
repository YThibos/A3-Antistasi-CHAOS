#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Collect BAR (Build And Resources / BARH) persistent state for inclusion in the
    Antistasi save file. Called from fn_saveLoop.sqf when A3A_hasBAR is true.

    Two kinds of state are saved:

    1. BAR-placed structures (dragon's teeth, fortifications, etc.) within the HQ build
       radius, via the BARH mod's own export function.  Only structures inside the build
       zone are exported so that natural terrain objects are never captured.

    2. Current resource amounts in each live BAR crate (keyed by world position).
       The garrison save/load system recreates crate objects from class+pos, but does not
       preserve mod-specific variables, so each crate's resource level would otherwise
       reset to the BAR default on reload.

    BAR Persistency API used (verify against the installed BARH version):
        BARH_fnc_Persistency_Export  - callable as:
            private _data = [_hqPos, _radius] call BARH_fnc_Persistency_Export;
        Returns an array that BARH_fnc_Persistency_Import can reconstruct.

Arguments:
    none

Return Value:
    <ARRAY> [_structureData, _crateResources]
        _structureData  : opaque array from BARH_fnc_Persistency_Export, or [] on error
        _crateResources : array of [posWorld, amount] for each live BAR crate

Scope: Server
Environment: Unscheduled (called from fn_saveLoop)
Public: No
*/

if (!isServer) exitWith { [[], []] };

// ---- 1. BAR structure export ------------------------------------------------
private _structureData = [];
if (isNil "BARH_fnc_Persistency_Export") then {
    Warn("barSave: BARH_fnc_Persistency_Export not found - BAR structures will not be saved");
} else {
    private _hqPos  = getMarkerPos "Synd_HQ";
    private _radius = call A3A_fnc_hqBuildRadius;
    _structureData = [_hqPos, _radius] call BARH_fnc_Persistency_Export;
    if (isNil "_structureData") then { _structureData = [] };
    Info_2("barSave: exported %1 BAR structure record(s) within %2 m of HQ",
        count _structureData, _radius);
};

// ---- 2. BAR crate resource snapshot -----------------------------------------
private _crateClasses = ["RessourceCrate_Concrete","RessourceCrate_Metal",
                         "RessourceCrate_Sand","RessourceCrate_Wood"];
private _crateResources = [];
{
    private _crate = _x;
    if (!alive _crate) then { continue };
    private _amount = _crate getVariable ["BARH_ressources", -1];
    // -1 means BAR hasn't set this variable yet; skip (keep BAR's own default on reload)
    if (_amount < 0) then { continue };
    _crateResources pushBack [getPosWorld _crate, _amount];
} forEach (
    allMissionObjects "RessourceCrate_Concrete"
    + allMissionObjects "RessourceCrate_Metal"
    + allMissionObjects "RessourceCrate_Sand"
    + allMissionObjects "RessourceCrate_Wood"
);

Info_1("barSave: saved resource amounts for %1 BAR crate(s)", count _crateResources);

[_structureData, _crateResources]

