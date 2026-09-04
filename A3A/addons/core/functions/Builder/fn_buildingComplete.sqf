/*
Description:
    Server-side function to complete or cancel a construction

Environment: Server, unscheduled
Arguments:
    1. <object> Plank object to complete construction for
    2. <bool> True if completed, false if cancelled
*/

#include "..\..\Includes\siteTiers.hpp"

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

private _class = typeOf _building;

// Add to garrison data if it's within one.
//
// CHAOS: two bugs used to make this unreliable, and both threw rather than
// mis-filed anything, which is why the tier recompute at the bottom of this
// file never ran on a real build.
//   1. fn_getMarkerForPos returns "" for a position inside no marker at all -
//      the normal case for a structure put down at the edge of a small resource
//      or factory marker. sidesX getVariable "" is nil, and comparing nil to a
//      side throws, aborting the whole function.
//   2. _className was never declared here (this function takes _target and
//      _finished), so the flag test below threw on every completed build.
private _marker = [getPosATL _building] call A3A_fnc_getMarkerForPos;
if (_marker != "" && { (sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer }) then {
    [_marker, _building] call A3A_fnc_garrisonServer_addVehicle;
} else {
    // CHAOS: site-upgrade structures only. The RTS placer puts the warehouse down
    // near the delivered container, which the player parks wherever the ground
    // allows - routinely just outside a small marker's own outline. Claim it for
    // the nearest rebel-held resource or factory within the site claim radius, so
    // it lands in that garrison's record, which is exactly what A3A_fnc_siteTiers
    // reads and what the save carries.
    //
    // Deliberately NOT applied to ordinary construction: re-homing every fence
    // built near a mine into that mine's garrison would move it onto the zone's
    // spawn/despawn cycle and into its build-cost accounting, which is a much
    // bigger behaviour change than this feature needs.
    private _siteCandidates = [];
    if (_class in TIER_STRUCTURE_CLASSES) then {
        _siteCandidates = (resourcesX + factories) select {
            ((sidesX getVariable [_x, sideUnknown]) isEqualTo teamPlayer)
            && { (_building distance2D markerPos _x) <= (([_x] call A3A_fnc_garrisonVehicleRadius) max SITE_CLAIM_RADIUS) }
        };
    };
    if (_siteCandidates isNotEqualTo []) then {
        private _nearest = [_siteCandidates, [], { _building distance2D markerPos _x }, "ASCEND"] call BIS_fnc_sortBy;
        [_nearest # 0, _building] call A3A_fnc_garrisonServer_addVehicle;
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

// CHAOS: a buildable that is ALSO a registered utility item (the BAR resource
// depot) needs the utility-item init to run on it, or the built copy is a bare
// prop: no "barsupply" resupply action, no "noclear" cargo protection, no
// initial BAR stock. Calling the shared init is deliberate - duplicating those
// three behaviours here would let the build and respawn paths drift apart.
//
// Ordering matters. This runs AFTER the garrison attribution above, so markerX
// is already set by the time initObject's "save" flag spawns
// fn_rebelVehPlacedWorker; that worker exits early on a vehicle that already has
// a marker, so no second garrison entry is created. Nothing else here relies on
// initObject, so the null check simply covers garrisonServer_addVehicle deleting
// the object when its marker is despawned.
if (!isNull _building && {_class in A3A_utilityItemHM}) then {
    _building call A3A_fnc_initObject;
    // initObject sets A3A_itemPrice from the catalogue, which is -1 for a
    // build-only item. Overwrite it with what the build actually cost so the
    // garage refunds the right amount if the structure is stored again.
    private _buildPrice = _target getVariable ["A3A_build_price", 0];
    if (_buildPrice > 0) then { _building setVariable ["A3A_itemPrice", _buildPrice, true] };
};

// Allowing flagpole construction is probably not a good idea due to how markerChange handles flags atm
if (_class isEqualTo (A3A_faction_reb get "flag")) then {
    _building setFlagTexture (A3A_faction_reb get "flagTexture");
};

// CHAOS: a site upgrade structure changes the tier of the resource or factory it
// stands on, and tier decides supply-graph membership and income. Recompute now
// rather than waiting for the income tick, so the player sees the site join the
// network as soon as the build finishes. A3A_fnc_siteTiers derives tiers from the
// structures present, so nothing needs recording here - the building IS the state.
if (_class in TIER_STRUCTURE_CLASSES) then {
    call A3A_fnc_siteTiers;
    [] call A3A_fnc_refreshSupplyGraph;
};
