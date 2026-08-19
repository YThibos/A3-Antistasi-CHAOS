#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Transfer resources from a BAR RessourceDepot to all nearby BAR crates.

    Delegates the actual transfer to BuildAndRessources_fnc_transferDepotToCrate
    (verified from BuildAndRessources.pbo source).  That function handles:
      - resource-type matching between depot and crate
      - capacity clamping
      - atomic depot-deduction + crate-fill with rollback on mismatch
      - infinite-stock depots (stock == -1)

    BAR's transfer function also validates that the depot is within the crate's
    "nearest depot" radius (default 50 m per BuildAndRessources_depotTransferRadius).
    We search using that same radius so only reachable crates are attempted.

    This function runs on the SERVER (fn_barResupply is remoteExec'd there by the
    utility-item purchase handler).  Calling transferDepotToCrate directly (not via
    remoteExecCall) bypasses its caller-distance check, which is intentional: the
    server is acting on the depot on the player's behalf.

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

// BAR depot transfer radius (CBA setting, default 50 m).
private _radius = _depot getVariable ["BuildAndRessources_depotTransferRadius", 50];

private _crateClasses = ["RessourceCrate_Concrete", "RessourceCrate_Wood",
                          "RessourceCrate_Sand",     "RessourceCrate_Metal"];
private _nearbyCrates = (nearestObjects [_depot, _crateClasses, _radius]) select { alive _x };

if (_nearbyCrates isEqualTo []) exitWith {
    [_titleStr, format [localize "STR_A3A_Utility_Items_BAR_Resupply_None", round _radius]]
        remoteExec ["A3A_fnc_customHint", _player];
};

private _resupplied = 0;
{
    private _result = [_depot, _x] call BuildAndRessources_fnc_transferDepotToCrate;
    // result = [transferred, crateAmount, crateCapacity, depotAmount, depotCapacity]
    if ((_result#0) > 0) then { _resupplied = _resupplied + 1 };
    Debug_3("barResupply: crate %1 received %2 (result: %3)", typeOf _x, _result#0, _result);
} forEach _nearbyCrates;

[_titleStr, format [localize "STR_A3A_Utility_Items_BAR_Resupply_Sent", _resupplied]]
    remoteExec ["A3A_fnc_customHint", _player];
