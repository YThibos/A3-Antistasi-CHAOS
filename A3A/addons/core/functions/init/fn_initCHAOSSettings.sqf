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
    ["[CHAOS] Antistasi", "Map Overlay"],
    true,    // default: enabled
    0,
    {},
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceShowClaimAreas",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_mapOverlay_claims", localize "STR_A3A_CHAOS_mapOverlay_claims_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
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
    ["[CHAOS] Antistasi", "Map Overlay"],
    [100, 1400, 800, 0],    // min, max, default, 0 decimal places
    // GLOBAL, not per-client. This number defines the shape of the world: the
    // server derives supply connectivity from it in A3A_fnc_computeSupplyGraph,
    // so every machine has to agree on it. It was per-client while the overlay
    // was pure decoration, which merely meant two players saw slightly
    // different borders; that is no longer harmless. Presentation settings
    // (fill, thickness, opacity, claim areas, enable) stay per-client below.
    2,                      // server forces setting on clients
    _invalidate,
    false
] call CBA_fnc_addSetting;

// How far territory stretches into empty ground, as a multiple of the
// influence range above. The range decides how hard a position pushes; this
// decides how far its territory reaches to meet a neighbour across ground
// neither of them actually holds, so the two jobs stop fighting each other.
// 0..3 in half steps: 0 is off (hard gaps), and 2.0 covers about the p90 of
// Altis objective spacing at the 800 m default range, leaving only the worst
// few gaps as no-man's-land in exchange for a crisper contour.
[
    "A3A_CHAOS_influenceReach",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_reach", localize "STR_A3A_CHAOS_mapOverlay_reach_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
    [0, 3.0, 2.0, 1],       // min, max, default, 1 decimal place
    // GLOBAL for the same reason as the range above: it multiplies every
    // radius, so it moves both the drawn border and the supply corridors.
    2,                      // server forces setting on clients
    _invalidate,
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceThickness",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_thickness", localize "STR_A3A_CHAOS_mapOverlay_thickness_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
    [1, 8, 4, 0],           // min, max, default, 0 decimal places
    0,
    {},                     // drawn per frame, no recompute needed
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceFill",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_mapOverlay_fill", localize "STR_A3A_CHAOS_mapOverlay_fill_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
    false,   // default: outline only
    0,
    _invalidate,            // the fill triangles are only built when this is on
    false
] call CBA_fnc_addSetting;

[
    "A3A_CHAOS_influenceFillOpacity",
    "SLIDER",
    [localize "STR_A3A_CHAOS_mapOverlay_fillOpacity", localize "STR_A3A_CHAOS_mapOverlay_fillOpacity_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
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
    ["[CHAOS] Antistasi", "Construction"],
    [0.1, 5.0, 1.0, 1],   // min, max, default, decimal places
    2,                     // isGlobal: server setting, broadcast to all clients
    {},
    true                   // server can force this value on clients
] call CBA_fnc_addSetting;

// ---- Arsenal ----
[
    "chaos_arsenal_useAce",
    "CHECKBOX",
    [
        "Use ACE Arsenal",
        "When enabled, uses ACE Arsenal instead of Jeroen's Arsenal with full stock enforcement and guest membership limits."
    ],
    ["[CHAOS] Antistasi", "Arsenal"],
    false,                 // default: false (Legacy JNA)
    2,                     // isGlobal: server setting synced to clients
    {},
    true                   // server forces setting on clients
] call CBA_fnc_addSetting;

[
    "chaos_arsenal_enforceGuestLimits",
    "CHECKBOX",
    [
        "Enforce Guest Limits in ACE Arsenal",
        "Apply non-member guest item restrictions to ACE Arsenal item availability."
    ],
    ["[CHAOS] Antistasi", "Arsenal"],
    true,                  // default: true
    2,
    {},
    true
] call CBA_fnc_addSetting;

[
    "chaos_arsenal_allowDefaultLoadouts",
    "CHECKBOX",
    [
        "Allow Default Loadouts in ACE Arsenal",
        "Allow loading default faction/role loadouts in ACE Arsenal."
    ],
    ["[CHAOS] Antistasi", "Arsenal"],
    true,                  // default: true
    2,
    {},
    true
] call CBA_fnc_addSetting;

// ============================================================================
// ==  Supply network                                                        ==
// ============================================================================

// Drawing the supply edges is presentation, so it is per-client like the rest
// of the overlay's appearance settings.
[
    "A3A_CHAOS_supplyShowEdges",
    "CHECKBOX",
    [localize "STR_A3A_CHAOS_supply_showEdges", localize "STR_A3A_CHAOS_supply_showEdges_tt"],
    ["[CHAOS] Antistasi", "Map Overlay"],
    true,
    0,
    {},
    false
] call CBA_fnc_addSetting;

// How much of its rate a fully severed faction keeps. Global: it is a balance
// number the server owns, and A3A_fnc_supplyRateMultiplier reads it server-side
// anyway. Zero is allowed but not advised - a faction on no resources stops
// attacking entirely, which makes for a very quiet endgame.
//
// Default raised 0.5 -> 0.75 ahead of replenishment gating (see RESEARCH.md).
// Once a severed marker cannot be reinforced at all, whatever the pool holds,
// this multiplier stops being the mechanic and becomes a nudge: at the cut
// markers it is redundant, and at the still-connected ones it punishes them for
// damage done elsewhere. 0.75 keeps the pressure without stacking a third
// penalty onto a faction that is already losing minor sites as it loses ground
// (fn_updateMinorSites sizes each side's camp network by markers owned).
[
    "A3A_CHAOS_supplyRateFloor",
    "SLIDER",
    [localize "STR_A3A_CHAOS_supply_rateFloor", localize "STR_A3A_CHAOS_supply_rateFloor_tt"],
    ["[CHAOS] Antistasi", "Supply"],
    [0, 1, 0.75, 2],
    2,                      // server forces setting on clients
    {},
    false
] call CBA_fnc_addSetting;

// BAR material produced per connected rebel factory per income tick, split
// evenly over the four materials. Global: it is production balance.
[
    "A3A_CHAOS_barFactoryYield",
    "SLIDER",
    [localize "STR_A3A_CHAOS_supply_factoryYield", localize "STR_A3A_CHAOS_supply_factoryYield_tt"],
    ["[CHAOS] Antistasi", "Supply"],
    [0, 1000, 200, 0],
    2,                      // server forces setting on clients
    {},
    false
] call CBA_fnc_addSetting;

// Ceiling per material per depot. This is the reason to build more depots
// rather than one bottomless one.
[
    "A3A_CHAOS_barDepotCap",
    "SLIDER",
    [localize "STR_A3A_CHAOS_supply_depotCap", localize "STR_A3A_CHAOS_supply_depotCap_tt"],
    ["[CHAOS] Antistasi", "Supply"],
    [500, 20000, 3000, 0],
    2,                      // server forces setting on clients
    {},
    false
] call CBA_fnc_addSetting;

// Hard ceiling on the length of a supply edge. The radius-derived candidate test
// reaches 4 km between outposts and 5.6 km airfield to airfield at the Altis
// defaults, which is far enough that a side holding most of the map links
// everything to everything - measured in game as a solid fan of lines from every
// marker. This is the cutoff that turns it back into a neighbour network.
[
    "A3A_CHAOS_supplyMaxEdge",
    "SLIDER",
    [localize "STR_A3A_CHAOS_supply_maxEdge", localize "STR_A3A_CHAOS_supply_maxEdge_tt"],
    ["[CHAOS] Antistasi", "Supply"],
    [500, 5000, 1500, 0],
    2,                      // server forces setting on clients
    {},
    false
] call CBA_fnc_addSetting;

// Links kept per node, shortest first. The distance cap alone still leaves a
// dense cluster fully meshed, so this thins it. Applied AFTER the corridor test,
// as a symmetric union - a pruned edge is one that was genuinely available and
// simply lost to nearer neighbours, never one that failed on the ground.
[
    "A3A_CHAOS_supplyMaxLinks",
    "SLIDER",
    [localize "STR_A3A_CHAOS_supply_maxLinks", localize "STR_A3A_CHAOS_supply_maxLinks_tt"],
    ["[CHAOS] Antistasi", "Supply"],
    [1, 10, 3, 0],
    2,                      // server forces setting on clients
    {},
    false
] call CBA_fnc_addSetting;
