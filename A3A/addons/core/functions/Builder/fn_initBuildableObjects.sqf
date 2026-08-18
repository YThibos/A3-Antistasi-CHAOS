/*
Author: [Killerswin2]
    creates the buildable object list on clients.
Arguments:
    None
Return Value:
NONE
Scope: Client
Environment: Unscheduled
Public:
no
Example:
call A3A_fnc_initBuildableObjects;
*/

private _mapInfo = missionConfigFile/"A3A"/"mapInfo"/toLower worldName;
if (!isClass _mapInfo) then {_mapInfo = configFile/"A3A"/"mapInfo"/toLower worldName};
A3A_buildableObjects = getArray (_mapInfo/"buildObjects");

A3A_buildingPriceHM = createHashMapFromArray A3A_buildableObjects; // you can feed 3-element arrays to createHashMapFromArray, it will ignore anything after the first two for each entry

// WP4b: append global military-tier (basetier) catalogue.
// Uses vanilla structures available on all maps.
// Only adds entries not already present in the map's own buildObjects[].
// The basetier ability gates each entry behind the Construction Yard (see fn_teamLeaderRTSPlacerDialog.sqf).
{
    if !(_x#0 in A3A_buildingPriceHM) then {
        A3A_buildableObjects pushBack _x;
        A3A_buildingPriceHM set [_x#0, _x];
    };
} forEach [
    ["Land_Cargo_Tower_V1_F",      3000, "basetier"],
    ["Land_Cargo_Patrol_V1_F",     1200, "basetier"],
    ["Land_Cargo_House_V1_F",       900, "basetier"],
    ["Land_HBarrierTower_F",        800, "basetier"],
    ["Land_HBarrierBig_F",          250, "basetier"],
    ["Land_HBarrier_5_F",           120, "basetier"],
    ["Land_CncWall4_F",             150, "basetier"],
    ["Land_CncBarrierMedium4_F",    100, "basetier"],
    ["Land_Razorwire_F",             60, "basetier"],
    ["Land_Net_Fence_4m_F",          40, "basetier"]
];

A3A_buildableObjects
