#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Restore BAR (Build And Resources / BARH) state saved by fn_barSave.sqf.
    Called from fn_loadServer.sqf when A3A_hasBAR is true.

    1. Calls BARH_fnc_Persistency_Import to recreate placed BAR structures.

    2. Sets up an EntityCreated mission event handler that patches the resource amount
       on every BAR crate the garrison system spawns.  The handler removes itself once
       all expected crates have been found (or when the lookup map is empty).

    BAR Persistency API used (verify against the installed BARH version):
        BARH_fnc_Persistency_Import  - callable as:
            [_data] call BARH_fnc_Persistency_Import;
        where _data is the opaque array returned by BARH_fnc_Persistency_Export.

Arguments:
    0: <ARRAY> [_structureData, _crateResources]   (value of A3A_barSaveData)

Return Value:
    <nil>

Scope: Server
Environment: Unscheduled (called from fn_loadServer)
Public: No
*/
params [
    ["_saveData", [], [[]]]
];

if (!isServer) exitWith {};

_saveData params [
    ["_structureData",  [], [[]]],
    ["_crateResources", [], [[]]]
];

// ---- 1. Recreate BAR placed structures ---------------------------------------
if (_structureData isNotEqualTo []) then {
    if (isNil "BARH_fnc_Persistency_Import") then {
        Warn("barLoad: BARH_fnc_Persistency_Import not found - BAR structures cannot be restored");
    } else {
        [_structureData] call BARH_fnc_Persistency_Import;
        Info_1("barLoad: imported %1 BAR structure record(s)", count _structureData);
    };
};

// ---- 2. Restore crate resource amounts --------------------------------------
// The garrison recreates crate objects later (lazily when HQ garrison is spawned).
// Build a lookup: rounded world-position string -> amount, then watch for each crate
// and patch it as soon as it appears.

if (_crateResources isEqualTo []) exitWith {
    Info("barLoad: no crate resource data to restore");
};

// Build a lookup: rounded world-position key -> saved resource amount.
// Round to nearest 0.1 m to absorb floating-point drift across save/load.
private _lookup = createHashMap;
{
    private _pos = _x#0;
    private _key = format ["%1_%2_%3",
        round (_pos#0 * 10),
        round (_pos#1 * 10),
        round (_pos#2 * 10)];
    _lookup set [_key, _x#1];
} forEach _crateResources;

// Store in mission-namespace globals.  EH event handlers run in a fresh scope and
// cannot close over local variables, so A3A_ globals are the only bridge.
// The EH itself clears these once all crates have been patched.
A3A_barLoadPending = _lookup;

Info_1("barLoad: waiting to restore resources for %1 BAR crate(s)", count A3A_barLoadPending);

// EntityCreated fires on the server when the garrison spawner creates each crate.
A3A_barLoadEhID = addMissionEventHandler ["EntityCreated", {
    params ["_entity"];
    if (!(typeOf _entity in ["RessourceCrate_Concrete","RessourceCrate_Metal",
                              "RessourceCrate_Sand","RessourceCrate_Wood"])) exitWith {};

    private _pos = getPosWorld _entity;
    private _key = format ["%1_%2_%3",
        round (_pos#0 * 10),
        round (_pos#1 * 10),
        round (_pos#2 * 10)];

    private _savedAmt = A3A_barLoadPending getOrDefault [_key, -1];
    if (_savedAmt < 0) exitWith {};

    _entity setVariable ["BARH_ressources", _savedAmt, true];
    A3A_barLoadPending deleteAt _key;
    Debug_2("barLoad: restored %1 resources to crate at %2", _savedAmt, _pos);

    if (A3A_barLoadPending isEqualTo createHashMap) then {
        removeMissionEventHandler ["EntityCreated", A3A_barLoadEhID];
        Info("barLoad: all BAR crate resources restored; EntityCreated EH removed");
        A3A_barLoadPending = nil;
        A3A_barLoadEhID    = nil;
    };
}];

