#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Transfer resources from a BAR RessourceDepot to all nearby BAR resource crates.

    BAR only builds from crates within 50 m of the player; a depot's resources are
    otherwise inert until they reach the crates. This server-side function walks the
    crates within _resupplyRadius of the depot and fills each one up to its maximum,
    deducting the transferred amount from the depot.

    Resource variable names used by BAR (Build And Resources / BARH mod):
        Crate current amount : getVariable ["BARH_ressources",    0]
        Crate capacity       : getVariable ["BARH_ressourcesMax", 500]
        Depot concrete stock : getVariable ["BARH_ressources_concrete", 0]
        Depot metal stock    : getVariable ["BARH_ressources_metal",    0]
        Depot sand stock     : getVariable ["BARH_ressources_sand",     0]
        Depot wood stock     : getVariable ["BARH_ressources_wood",     0]
    These are set on the object and broadcast globally (last arg true).
    NOTE: verify against the installed BARH mod version before releasing.

Arguments:
    0: <OBJECT> The RessourceDepot object
    1: <OBJECT> The player who activated the action

Return Value:
    <nil>

Scope: Server
Environment: Unscheduled
Public: No
*/
params [
    ["_depot",  objNull, [objNull]],
    ["_player", objNull, [objNull]]
];

if (!isServer) exitWith {};
if (isNull _depot || isNull _player) exitWith {};

private _titleStr = localize "STR_A3A_Utility_Items_Purchase_Title";
private _resupplyRadius = 100;

// Map each crate class to the depot variable key that holds that resource type.
private _crateTypeMap = createHashMapFromArray [
    ["RessourceCrate_Concrete", "concrete"],
    ["RessourceCrate_Metal",    "metal"],
    ["RessourceCrate_Sand",     "sand"],
    ["RessourceCrate_Wood",     "wood"]
];

private _crateClasses = keys _crateTypeMap;

// Collect live BAR crates within range.
private _nearbyCrates = (nearestObjects [_depot, _crateClasses, _resupplyRadius])
    select { alive _x };

if (_nearbyCrates isEqualTo []) exitWith {
    [_titleStr, format [localize "STR_A3A_Utility_Items_BAR_Resupply_None", _resupplyRadius]]
        remoteExec ["A3A_fnc_customHint", _player];
};

private _resupplied = 0;

{
    private _crate = _x;
    private _type  = _crateTypeMap get (typeOf _crate);

    private _depotKey    = "BARH_ressources_" + _type;
    private _depotStock  = _depot getVariable [_depotKey, 0];
    if (_depotStock <= 0) then { continue };

    private _crateAmt = _crate getVariable ["BARH_ressources",    0];
    private _crateMax = _crate getVariable ["BARH_ressourcesMax", 500];
    if (_crateAmt >= _crateMax) then { continue };

    private _needed   = _crateMax - _crateAmt;
    private _transfer = _needed min _depotStock;

    _crate setVariable ["BARH_ressources",       _crateAmt + _transfer, true];
    _depot setVariable [_depotKey, _depotStock - _transfer,             true];

    _resupplied = _resupplied + 1;

    Debug_3("barResupply: depot %1 filled %2 crate of type %3",
        _depot, _transfer, _type);
} forEach _nearbyCrates;

[_titleStr, format [localize "STR_A3A_Utility_Items_BAR_Resupply_Sent", _resupplied]]
    remoteExec ["A3A_fnc_customHint", _player];

