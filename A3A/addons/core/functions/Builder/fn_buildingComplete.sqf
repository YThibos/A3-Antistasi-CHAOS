/*
Description:
    Server-side function to complete or cancel a construction

Environment: Server, unscheduled
Arguments:
    1. <object> Plank object to complete construction for
    2. <bool> True if completed, false if cancelled
*/

params ["_target", ["_finished", true]];

// Remove from list. Let it clear out nulls
A3A_unbuiltObjects deleteAt (A3A_unbuiltObjects find _target);
publicVariable "A3A_unbuiltObjects";
if (isNull _target) exitWith {};            // Possible if two engineers attempted to construct the same object, or a zeus delete
deleteVehicle _target;

// Cancel case
if (!_finished) exitWith {
    private _price = _target getVariable ["A3A_build_price", 10];
    if (_price > 0) then { [0, _price] spawn A3A_fnc_resourcesFIA };
};

// Repair case, just call the repair function
private _repairObj = _target getVariable "A3A_build_repairObj";
if (!isNil "_repairObj") exitWith {
    _repairObj call A3A_fnc_repairRuinedBuilding;
};

// Construction case, spawn the building
private _building = createVehicle [_target getVariable "A3A_build_class", [0,0,0], [], 0, "CAN_COLLIDE"];
_building setPosWorld (_target getVariable "A3A_build_pos");
_building setVectorDirAndUp (_target getVariable "A3A_build_dir");
_building setVariable ["A3A_building", true, true];            // Used to identify removable buildings

// Mark Construction Yard so fn_relocateHQObjects can find it by variable (same as utility-item path)
if (typeOf _building isEqualTo "a3a_constructionYard") then {
    _building setVariable ["A3A_isConstructionYard", true, true];
};

// Mark Air Control Center so fn_relocateHQObjects can find it by variable
if (typeOf _building isEqualTo "a3a_airControlCenter") then {
    _building setVariable ["A3A_isAirControlCenter", true, true];
};

// Add to garrison data if it's within one
private _marker = [getPosATL _building] call A3A_fnc_getMarkerForPos;
if (_marker != "" && { (sidesX getVariable [_marker, sideUnknown]) == teamPlayer }) then {
    [_marker, _building] call A3A_fnc_garrisonServer_addVehicle;
} else {
    // Proximity fallback for site upgrade structures placed near rebel resource or factory sites
    private _siteCandidates = (resourcesX + factories) select {
        (sidesX getVariable [_x, sideUnknown]) == teamPlayer &&
        { (_building distance2D markerPos _x) <= (([_x] call A3A_fnc_garrisonVehicleRadius) max 150) }
    };
    if (_siteCandidates isNotEqualTo []) then {
        _siteCandidates = [_siteCandidates, [], { _building distance2D markerPos _x }, "ASCEND"] call BIS_fnc_sortBy;
        [_siteCandidates # 0, _building] call A3A_fnc_garrisonServer_addVehicle;
    } else {
        // WP5b: If built within the HQ's current build radius, still attribute it to the HQ garrison
        // so it registers for calcBuildingReveal and calcBuildingCosts regardless of marker size.
        private _hqRadius = call A3A_fnc_hqBuildRadius;
        if ((_building distance2D (getMarkerPos "Synd_HQ")) <= _hqRadius) then {
            ["Synd_HQ", _building] call A3A_fnc_garrisonServer_addVehicle;
        } else {
            A3A_buildingsToSave pushBack _building;
        };
    };
};

// Allowing flagpole construction is probably not a good idea due to how markerChange handles flags atm
if (typeOf _building isEqualTo (A3A_faction_reb get "flag")) then {
    _building setFlagTexture (A3A_faction_reb get "flagTexture");
};

// CHAOS: a site upgrade structure changes the tier of the resource or factory it
// stands on, and tier decides supply-graph membership and income. Recompute now
// rather than waiting for the income tick, so the player sees the site join the
// network as soon as the build finishes. A3A_fnc_siteTiers derives tiers from the
// structures present, so nothing needs recording here - the building IS the state.
if (typeOf _building in ["a3a_warehouse", "Land_Warehouse_03_F", "Land_PowerGenerator_F"]) then {
    call A3A_fnc_siteTiers;
    [] call A3A_fnc_refreshSupplyGraph;
};
