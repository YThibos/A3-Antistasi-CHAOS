
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
#include "..\..\Includes\siteTiers.hpp"

params ["_oldBuilding", "_newBuilding", "_isRuin"];

Trace_5("%1 (%2) changed to %3 (%4) isRuin %5", typeof _oldBuilding, netId _oldBuilding, typeof _newBuilding, netId _newBuilding, _isRuin);

private _origBuilding = _oldBuilding getVariable ["building", _oldBuilding];
_newBuilding setVariable ["building", _origBuilding];           // works because these aren't terrain objects?

// TODO: Could try switching police station destruction to origBuilding instead of oldBuilding (destroy on ruin only)

// If it's a police station, mark as destroyed
// Might not be spawned, so can't depend on the furniture case
if (netId _oldBuilding in A3A_policeStations) then {                // In theory this could happen on load? Unlikely

    private _city = A3A_policeStations get netId _oldBuilding;
    A3A_garrison get _city set ["policeStation", false];
    A3A_garrisonSize set [_city, (A3A_garrisonSize get _city) - 4];
    A3A_spawnPlaceStats deleteAt _city;
    A3A_policeStations deleteAt netId _oldBuilding;
    ["TaskSucceeded", ["", "Police Station Destroyed"]] remoteExec ["BIS_fnc_showNotification", teamPlayer];

    // Delete any furniture
    private _attached = _oldBuilding getVariable ["A3A_furniture", []];
    { deleteVehicle _x } forEach _attached;

    // Delete police car from garrison because the spawn place won't be saved
    private _vehicles = A3A_garrison get _city get "vehicles";
    A3A_garrison get _city set ["vehicles", _vehicles select { _x#1 isEqualType [] }];
};

if (_isRuin) then {

    // TODO: this whole system doesn't work for buildings that have an intermediate damage model
    //_oldBuilding setVariable ["ruins", _newBuilding];           // this one probably doesn't work at all?

    if (_origBuilding in A3A_antennas) then {
        A3A_antennaRuins pushBack _newBuilding;
        private _mrk = [A3A_mrkAntennas, _origBuilding] call BIS_fnc_nearestPosition;
        _mrk setMarkerAlpha 0.5;
        if (isNil "serverInitDone") exitWith {};       // Don't notify on load
        ["TaskSucceeded", ["", "Radio Tower Destroyed"]] remoteExec ["BIS_fnc_showNotification", teamPlayer];
    };

    // Antenna dead/alive status is handled separately
    if !(_origBuilding in A3A_antennas) then {
        A3A_destroyedBuildings pushBack _origBuilding;
    };

    // CHAOS: a site's upgrade tier is derived from its garrison record, and
    // upstream never removes a destroyed building from one - the despawn/spawn
    // cycle would put the warehouse back intact and the site would stay Tier 1
    // with nothing standing on it. A3A_fnc_siteTiers reconciles the record
    // against the world, so all this has to do is run it while the wreck is
    // still there to be seen. Same shape as the police-station case above:
    // destruction is bookkeeping, and the bookkeeping happens here.
    //
    // Deferred by a frame's worth of time because BuildingChanged can fire
    // alongside the damage that caused it, and the reconcile only recognises a
    // structure as lost once `alive` on it is false.
    if (typeOf _origBuilding in TIER_STRUCTURE_CLASSES) then {
        [{
            call A3A_fnc_siteTiers;
            [true] call A3A_fnc_refreshSupplyGraph;
        }, [], 1] call CBA_fnc_waitAndExecute;
    };
};
