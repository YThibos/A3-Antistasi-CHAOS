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

// WP4b: append global military-tier (basetier) and airport-tier (airtier) catalogues.
// Uses vanilla structures available on all maps.
// Only adds entries not already present in the map's own buildObjects[].

// Construction Yard, Air Control Center, Resource Depot, and MCK structures
if !("a3a_constructionYard" in A3A_buildingPriceHM) then {
    A3A_buildableObjects pushBack ["a3a_constructionYard", 5000, "basetier"];
    A3A_buildingPriceHM set ["a3a_constructionYard", 5000];
};

if !("a3a_airControlCenter" in A3A_buildingPriceHM) then {
    A3A_buildableObjects pushBack ["a3a_airControlCenter", 8000, "basetier"];
    A3A_buildingPriceHM set ["a3a_airControlCenter", 8000];
};

if !("RessourceDepot" in A3A_buildingPriceHM) then {
    A3A_buildableObjects pushBack ["RessourceDepot", 3000, "basetier"];
    A3A_buildingPriceHM set ["RessourceDepot", 3000];
};

{
    private _class = _x#0;
    if (_class in A3A_buildingPriceHM) then {
        // Force override to make it basetier/airtier only and remove from generic BB
        private _idx = A3A_buildableObjects findIf { _x#0 == _class };
        if (_idx >= 0) then {
            A3A_buildableObjects set [_idx, _x];
        };
        A3A_buildingPriceHM set [_class, _x#1];
    } else {
        A3A_buildableObjects pushBack _x;
        A3A_buildingPriceHM set [_class, _x#1];
    };
} forEach [
    // Military base tier (Military Construction Kit)
    ["Land_PillboxBunker_01_hex_F",  1500, "basetier"],
    ["Land_Cargo_Tower_V1_F",        3000, "basetier"],
    ["Land_Cargo_Patrol_V1_F",       1200, "basetier"],
    ["Land_Cargo_House_V1_F",         900, "basetier"],
    ["Land_HBarrierTower_F",          800, "basetier"],
    ["Land_HBarrierBig_F",            250, "basetier"],
    ["Land_HBarrier_5_F",             120, "basetier"],
    ["Land_CncWall4_F",               150, "basetier"],
    ["Land_CncBarrierMedium4_F",      100, "basetier"],
    ["Land_Razorwire_F",               60, "basetier"],
    ["Land_Net_Fence_4m_F",            40, "basetier"],

    // Site upgrade tier (delivered by the site upgrade mission only).
    // "sitetier" is an EXCLUSIVE catalogue: fn_teamLeaderRTSPlacerDialog shows
    // only these when the builder box carries the flag, so the delivered
    // container cannot be used to build a whole base out at a remote mine.
    // Prices are the container's build budget, so they must match what the
    // mission puts on it - see A3A_Tasks_fnc_ECON_SiteUpgrade.
    // Only the warehouse is BUILT. The Tier 2 power generator is delivered as a
    // finished object and simply set down where the player wants it, so it never
    // enters a build catalogue.
    ["a3a_warehouse",          1500, "sitetier"],

    // Airport tier (Airport Construction Kit)
    ["Land_Hangar_F",                 5000, "airtier"],
    ["Land_TentHangar_V1_F",          4000, "airtier"],
    ["Land_Airport_01_hangar_F",      3500, "airtier"],
    ["Land_LandMark_F",                500, "airtier"],
    ["Land_Windsock_01_F",             150, "airtier"],
    ["Land_HelipadRescue_F",          1500, "airtier"],
    ["Land_HelipadCivil_F",           1500, "airtier"],
    ["Land_ConcretePlates_01_F",       100, "airtier"],
    ["Land_runway_edgelight",           50, "airtier"],
    ["Land_runway_edgelight_blue_F",    50, "airtier"],
    ["Land_Flush_Light_green_F",        50, "airtier"],
    ["Land_Flush_Light_yellow_F",       50, "airtier"],
    ["Land_Flush_Light_red_F",          50, "airtier"]
];

A3A_buildableObjects
