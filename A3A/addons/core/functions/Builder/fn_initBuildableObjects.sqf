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
// So the map's values are PRICES, not catalogue entries - A3A_fnc_calcBuildingCosts
// reads them as numbers. Every `set` below has to keep that shape; the appends
// used to store the whole 3-element entry, which made calcBuildingCosts add an
// array to a number and throw for any base holding one of those structures.

// WP4b: append global military-tier (basetier) and airport-tier (airtier) catalogues.
// Uses vanilla structures available on all maps.
// Only adds entries not already present in the map's own buildObjects[].

// Construction Yard — one per campaign, must be built inside the HQ radius, and is
// buildable from any standard construction kit. "constructionyard" ability is handled specially
// in fn_teamLeaderRTSPlacerDialog: disabled when a yard already exists or player is outside HQ.
if !("a3a_constructionYard" in A3A_buildingPriceHM) then {
    A3A_buildableObjects pushBack ["a3a_constructionYard", 5000, "constructionyard"];
    A3A_buildingPriceHM set ["a3a_constructionYard", 5000];
};

// Air Control Center — one per campaign, must be built inside the HQ radius, requires Construction Yard,
// and is buildable from standard construction kits. "aircontrolcenter" ability is handled specially
// in fn_teamLeaderRTSPlacerDialog: disabled when ACC exists, Yard missing, or outside HQ.
if !("a3a_airControlCenter" in A3A_buildingPriceHM) then {
    A3A_buildableObjects pushBack ["a3a_airControlCenter", 8000, "aircontrolcenter"];
    A3A_buildingPriceHM set ["a3a_airControlCenter", 8000];
};

// BAR resource depot - the only source of BAR building material in CHAOS.
// Built rather than bought, from any construction kit, and gated on an existing
// Construction Yard: the "bardepot" ability is handled specially in
// fn_teamLeaderRTSPlacerDialog, the same way "constructionyard"/"aircontrolcenter"
// are. Deliberately NOT tagged "basetier"/"airtier": those are exclusive kit
// catalogues, and requiring a 3000 credit military kit on top of the yard would
// gate BAR twice for no design reason. The class only exists when BAR is loaded.
if (missionNamespace getVariable ["A3A_hasBAR", false] && {!("RessourceDepot" in A3A_buildingPriceHM)}) then {
    A3A_buildableObjects pushBack ["RessourceDepot", 3000, "bardepot"];
    A3A_buildingPriceHM set ["RessourceDepot", 3000];
};

{
    if !(_x#0 in A3A_buildingPriceHM) then {
        A3A_buildableObjects pushBack _x;
        A3A_buildingPriceHM set [_x#0, _x#1];
    };
} forEach [
    // Military base tier (Military Construction Kit)
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
    ["a3a_warehouse",                1500, "sitetier"],

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
