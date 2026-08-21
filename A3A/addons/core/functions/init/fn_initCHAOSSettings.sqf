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

// ---- Map Overlay ----
// Every setting here is client-side (scope 0): the overlay is a personal view.
// The onChange callbacks only clear the cache signature, which makes
// A3A_fnc_refreshInfluenceZones recompute on the next drawn frame. They must
// not compute anything themselves: CBA fires them during settings init, long
// before the zone globals exist.
private _invalidate = { A3A_influenceSignature = nil };

[
    "A3A_CHAOS_influenceOverlayEnabled",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_mapOverlay_enable", localize "STR_A3A_CHAOS_mapOverlay_enable_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    true,    // default: enabled
    0,
    {},
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceShowClaimAreas",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_mapOverlay_claims", localize "STR_A3A_CHAOS_mapOverlay_claims_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    true,    // default: enabled
    0,
    {},
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceLinkDist",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_linkDist", localize "STR_A3A_CHAOS_mapOverlay_linkDist_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    [1000, 5000, 2000, 0],    // min, max, default, 0 decimal places
    0,
    _invalidate,
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceColour",
    "LIST",
    [localize "STR_A3A_CHAOS_mapOverlay_colour", localize "STR_A3A_CHAOS_mapOverlay_colour_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    [[0, 1, 2, 3, 4, 5, 6],
     ["Green", "Cyan", "Yellow", "White", "Blue", "Orange", "Purple"],
     0],    // default index 0 = Green
    0,
    {},
    false
] call CBA_fnc_addSetting;

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

