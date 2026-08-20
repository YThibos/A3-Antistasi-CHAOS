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
[
    "A3A_CHAOS_influenceOverlayEnabled",
    "CHECKBOX",
    [
        "Show influence zone overlay",
        "Draw transparent green circles (static-attribution radius) and filled triangles (zone-of-influence clusters) on the vanilla M-map for all friendly capturable positions."
    ],
    ["Antistasi CHAOS", "Map Overlay"],
    true,    // default: enabled
    0,       // client-side — each player controls their own view
    {},
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceTriangleDist",
    "SLIDER",
    [
        "Triangle zone max distance (m)",
        "Maximum distance between any two friendly zones to be considered connected for the triangle-of-influence algorithm. Applied rounded to the nearest 100 m. Affects both the BFS reachability graph and the per-pair triangle check."
    ],
    ["Antistasi CHAOS", "Map Overlay"],
    [1000, 5000, 2000, 0],    // min, max, default, 0 decimal places
    0,       // client-side
    {
        // If the map is currently open recompute immediately, otherwise mark dirty
        // so the overlay PFH picks it up on the next map-open.
        if (visibleMap && { !isNil "markersX" }) then {
            [] call A3A_fnc_computeInfluenceZones;
        } else {
            A3A_influenceZonesDirty = true;
        };
    },
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceColour",
    "LIST",
    [
        "Overlay colour",
        "Colour of the influence zone ellipses and filled triangle polygons drawn on the map."
    ],
    ["Antistasi CHAOS", "Map Overlay"],
    [[0, 1, 2, 3, 4, 5, 6],
     ["Green (default)", "Cyan", "Yellow", "White", "Blue", "Orange", "Purple"],
     0],    // default index 0 = Green
    0,      // client-side
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

