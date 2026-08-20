#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Draw event-handler for the influence zone overlay.
    Attached to the vanilla M-map control (display 12 ctrl 51) by
    A3A_fnc_initMapOverlay, and also to the Y-menu commander / fast-travel /
    garrison map controls by fn_mainDialog / fn_hqDialog.
    Called every frame while the map control renders.

    Draws cached data computed by A3A_fnc_computeInfluenceZones only — no
    computation here so the per-frame cost is negligible.

      • Semi-transparent coloured ellipses: static-attribution radius for every
        friendly capturable zone.
      • More-transparent coloured filled polygons: each validated triangle of
        compact friendly zones (zone-of-influence clusters).

Arguments:
    <CONTROL> Map control passed by the Draw EH machinery

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    A3A_influenceEllipses   (array, set by A3A_fnc_computeInfluenceZones)
    A3A_influenceTriangles  (array, set by A3A_fnc_computeInfluenceZones)
    A3A_CHAOS_influenceOverlayEnabled (CBA setting)
    A3A_CHAOS_influenceColour         (CBA setting: 0-6 colour index)
*/

params ["_map"];

// Bail out if overlay is disabled in CBA Addon Options
if !(missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]) exitWith {};

// Guard: the Draw EH fires whenever the control renders — skip if not visible
if (!visibleMap) exitWith {};

// ── Colour lookup ─────────────────────────────────────────────────────────
// Index matches the A3A_CHAOS_influenceColour LIST setting order.
// Each entry is [R, G, B] (alpha added separately for ellipses vs triangles).
private _colIdx = missionNamespace getVariable ["A3A_CHAOS_influenceColour", 0];
private _rgb = [
    [0,   0.6, 0.2],   // 0  Green (default)
    [0,   0.8, 0.8],   // 1  Cyan
    [0.9, 0.8, 0  ],   // 2  Yellow
    [0.9, 0.9, 0.9],   // 3  White
    [0.1, 0.3, 0.9],   // 4  Blue
    [0.9, 0.4, 0  ],   // 5  Orange
    [0.7, 0,   0.9]    // 6  Purple
] param [_colIdx, [0, 0.6, 0.2]];

private _ellCol  = _rgb + [0.18];   // ellipses: slightly opaque
private _polyCol = _rgb + [0.08];   // triangles: more transparent

// ── Ellipses ──────────────────────────────────────────────────────────────
if (!isNil "A3A_influenceEllipses" && { !(A3A_influenceEllipses isEqualTo []) }) then {
    {
        _x params ["_pos", "_sA", "_sB", "_angle"];
        _map drawEllipse [_pos, _sA, _sB, _angle, _ellCol, ""];
    } forEach A3A_influenceEllipses;
};

// ── Zone-of-influence triangles ───────────────────────────────────────────
if (!isNil "A3A_influenceTriangles" && { !(A3A_influenceTriangles isEqualTo []) }) then {
    {
        _map drawPolygon [_x, _polyCol, ""];
    } forEach A3A_influenceTriangles;
};

