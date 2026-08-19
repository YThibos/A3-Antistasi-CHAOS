#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Registers CBA Addon Options settings for CHAOS-specific features.
    Runs at preInit so settings appear in Addon Options before any mission loads.

Scope: All
Environment: Unscheduled (preInit)
Public: No
*/

// ---- Construction ----
[
    "A3A_CHAOS_buildTimeMult",
    "SLIDER",
    [
        "Build time multiplier",
        "Multiplier applied to all Antistasi build-box construction times and BAR structure placement times. " +
        "Default 1.0 = unchanged. " +
        "Note: ACE Fortify's own 'Time-Cost Coefficient' setting has no effect on either system - " +
        "Antistasi build boxes use vanilla hold-actions and BAR only checks ACE_Fortify as an item prerequisite."
    ],
    ["Antistasi CHAOS", "Construction"],
    [0.1, 5.0, 1.0, 1],   // min, max, default, decimal places
    2,                     // isGlobal: server setting, broadcast to all clients
    {},
    true                   // server can force this value on clients
] call CBA_fnc_addSetting;

