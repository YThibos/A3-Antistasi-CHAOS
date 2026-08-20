/*
Author: Antistasi CHAOS
    Whether the faction owns a Construction Yard.

    Single source of truth for the yard gate. The yard is identified by class plus one of
    two variables, so scenery of the same class (there is none: a3a_constructionYard is a
    fork class) and the garage placer's local ghost object cannot satisfy it. A yard that
    is still under construction counts, matching the build catalogue's own behaviour.

Arguments:
    none

Return Value:
    <Bool> true if a Construction Yard is placed or being built

Scope: Anywhere
Environment: Unscheduled
Public: Yes
Dependencies:
    A3A_isConstructionYard / A3A_building object variables (both public)

Example:
    if (call A3A_fnc_hasConstructionYard) then { ... };
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

(allMissionObjects "a3a_constructionYard") findIf {
    (_x getVariable ["A3A_isConstructionYard", false]) || (_x getVariable ["A3A_building", false])
} != -1
