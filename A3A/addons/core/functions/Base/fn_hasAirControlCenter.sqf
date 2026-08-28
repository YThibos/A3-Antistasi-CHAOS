/*
Author: Antistasi CHAOS
    Whether the faction owns an Air Control Center.

    Single source of truth for the ACC gate. The ACC is identified by class plus one of
    two variables, so the garage placer's local ghost object cannot satisfy it. An ACC that
    is still under construction counts, matching the build catalogue's own behaviour.

Arguments:
    none

Return Value:
    <Bool> true if an Air Control Center is placed or being built

Scope: Anywhere
Environment: Unscheduled
Public: Yes
Dependencies:
    A3A_isAirControlCenter / A3A_building object variables (both public)

Example:
    if (call A3A_fnc_hasAirControlCenter) then { ... };
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

(allMissionObjects "a3a_airControlCenter") findIf {
    (_x getVariable ["A3A_isAirControlCenter", false]) || (_x getVariable ["A3A_building", false])
} != -1
