/*
Author: Antistasi CHAOS
    Radius, in metres, of the HQ build area.

    Grows with the war tier, so a fresh HQ is a small fortified pocket and a late-game
    one can be built out properly. Single source of truth: the placer, the build-action
    range, the garrison attribution in buildingComplete, the Construction Yard gate and
    BAR structure persistence all read this, so they cannot drift apart.

Arguments:
    none

Return Value:
    <Number> Radius in metres. 75 at war tier 1, 210 at war tier 10.

Scope: Anywhere
Environment: Unscheduled
Public: Yes
Dependencies:
    tierWar (global, public)

Example:
    private _radius = call A3A_fnc_hqBuildRadius;
*/
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

75 + 15 * ((tierWar max 1) - 1)
