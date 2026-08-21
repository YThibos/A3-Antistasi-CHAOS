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
// There is no colour setting: each side is drawn in its own faction colour,
// read from CfgMarkerColors via colorTeamPlayer / colorOccupants /
// colorInvaders, so the overlay matches the map's own markers automatically.
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

// Reference influence range. Mirrors the upstream "spawn distance" slider
// idiom (fn_adminTab: 600-1400 in steps of 100) - same step, same top end -
// because both are "how far does this reach" distances in the same units and
// players already have a feel for that scale. Per-zone-type multipliers in
// A3A_fnc_zoneInfluenceRadii scale off this number.
[
    "A3A_CHAOS_influenceRange",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_range", localize "STR_A3A_CHAOS_mapOverlay_range_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    [100, 1400, 800, 0],    // min, max, default, 0 decimal places
    0,
    _invalidate,
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceThickness",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_thickness", localize "STR_A3A_CHAOS_mapOverlay_thickness_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    [1, 8, 4, 0],           // min, max, default, 0 decimal places
    0,
    {},                     // drawn per frame, no recompute needed
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceFill",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_mapOverlay_fill", localize "STR_A3A_CHAOS_mapOverlay_fill_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    false,   // default: outline only
    0,
    _invalidate,            // the fill triangles are only built when this is on
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceFillOpacity",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_fillOpacity", localize "STR_A3A_CHAOS_mapOverlay_fillOpacity_tt"],
    ["Antistasi CHAOS", "Map Overlay"],
    [0.02, 0.8, 0.25, 2],   // min, max, default, 2 decimal places
    0,
    {},                     // read per frame, no recompute needed
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

