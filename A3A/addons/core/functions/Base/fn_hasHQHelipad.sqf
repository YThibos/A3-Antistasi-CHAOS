/*
Author: Antistasi CHAOS
    Whether the faction has a helipad inside the HQ build radius.

    Single source of truth for the "the HQ can handle rotary traffic" gate, shared by the
    garage's store path (A3A_fnc_addVehicle / fn_buildContextMenu) and its retrieve path
    (HR_GRG_fnc_toggleConfirmBttn), so the button a player sees and the check the server
    runs cannot drift apart.

    A built pad is found by class enumeration, not by a positional sweep: "a3a_helipad" is a
    build-catalogue class (mapInfo buildObjects[], 1500 credits) that only the construction
    system ever creates, so allMissionObjects on that one class IS the build system's record
    of placed pads - it costs nothing and it cannot be fooled by scenery.

    The terrain sweep afterwards is deliberate and secondary. allMissionObjects never returns
    map scenery, and HR_GRG_fnc_toggleConfirmBttn has always let a player take a helicopter
    out next to a pad that came with the terrain. Dropping that would tighten the retrieve
    path, which this change must not do, so any Helipad_Base_F inside the radius counts too.

    A pad still under construction does NOT count - unlike the Construction Yard and the ACC
    gates, this one is about a surface a helicopter can actually be set down on.

Arguments:
    none

Return Value:
    <Bool> true if a built helipad stands within the current HQ build radius

Scope: Anywhere
Environment: Unscheduled
Public: Yes
Dependencies:
    A3A_fnc_hqBuildRadius, the "Synd_HQ" marker

Example:
    if (call A3A_fnc_hasHQHelipad) then { ... };
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

private _hqPos = getMarkerPos "Synd_HQ";
if (_hqPos isEqualTo [0,0,0]) exitWith { false };

private _radius = call A3A_fnc_hqBuildRadius;

if ((allMissionObjects "a3a_helipad") findIf { (_x distance2D _hqPos) <= _radius } != -1) exitWith { true };

(count (nearestObjects [_hqPos, ["Helipad_Base_F"], _radius, true])) > 0
