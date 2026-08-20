#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Draw event-handler for the vanilla M-map influence zone overlay.
    Registered on display 12 / control 51 (the M-button map) by
    A3A_fnc_initMapOverlay; called every frame while the map is open.

    Draws cached data computed by A3A_fnc_computeInfluenceZones only — no
    computation here so the per-frame cost stays negligible.

      • Semi-transparent green ellipses: static-attribution radius for every
        friendly capturable zone.
      • More-transparent green filled polygons: each validated triangle of
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
*/

params ["_map"];

// Bail out if overlay is disabled in CBA Addon Options
if !(missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]) exitWith {};

// Extra guard: the Draw EH fires whenever the control renders; visibleMap
// should always be true here, but defend against edge cases.
if (!visibleMap) exitWith {};

// ── Ellipses ──────────────────────────────────────────────────────────────
if (!isNil "A3A_influenceEllipses") then {
    private _col = [0, 0.55, 0.2, 0.15];
    {
        _x params ["_pos", "_sA", "_sB", "_angle"];
        _map drawEllipse [_pos, _sA, _sB, _angle, _col, ""];
    } forEach A3A_influenceEllipses;
};

// ── Zone-of-influence triangles ───────────────────────────────────────────
if (!isNil "A3A_influenceTriangles") then {
    private _col = [0, 0.55, 0.2, 0.08];
    {
        _map drawPolygon [_x, _col, ""];
    } forEach A3A_influenceTriangles;
};

