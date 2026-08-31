#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Draw event handler for the zone-of-influence overlay ("borders"). Attached
    to the vanilla M-map control by A3A_fnc_initMapOverlay and to the Y-menu
    commander / fast-travel / garrison map controls by fn_mainDialog and
    fn_hqDialog. Fires once per frame per map control that renders.

    Draws three layers, bottom to top:
      - the fill: each side's territory as filled triangles, off by default.
      - the border: each side's territory outline, as line segments.
      - the claim areas: each friendly zone's static-attribution footprint, in
        the marker's own shape, so what you see is what A3A_fnc_getMarkerForPos
        will actually claim.

    All geometry comes from the cache. The only work done here is the throttled
    staleness check in A3A_fnc_refreshInfluenceZones, which does a cheap
    signature comparison at most twice a second and only recomputes when the
    territory actually changed.

    ---- Line thickness ------------------------------------------------------
    drawLine has no width parameter, so thickness is drawn as N parallel copies
    of each segment, offset perpendicular to it by whole screen pixels. The
    perpendicular unit vector is precomputed per segment by
    fn_computeInfluenceZones, and the metres-per-pixel factor is derived once
    per frame from the control's own screen-to-world mapping, so the band keeps
    a constant width on screen at every zoom level.

    That also answers the "dashed at high zoom" look in the captain's
    screenshot: the contour is provably closed - every vertex is shared by
    exactly two segment ends, verified across the whole test matrix - so the
    gaps are a hairline rasterisation artifact, not missing geometry. Anything
    above thickness 1 fills them in.

    A line budget caps the total number of drawLine calls. It is a safety net
    for a late-game map at maximum thickness, not something the default ever
    hits; when it bites, the thickness is reduced rather than segments dropped,
    so the border never becomes discontinuous.

    ---- Fill ----------------------------------------------------------------
    drawPolygon cannot fill - the Biki is explicit that it draws an outline only
    and points at drawTriangle as the workaround - so the fill is a triangle
    soup produced by fn_computeInfluenceZones and handed to drawTriangle in one
    call per side. Concavity is a non-issue because every triangle is convex by
    construction, and enclosed pockets need no special handling: a pocket
    inside your territory belongs to another side and is painted by that side's
    own pass.

    Note: no visibleMap guard. visibleMap is only true for the vanilla map, so
    guarding on it would silently disable every dialog map, and a Draw EH does
    not fire unless its control is rendering anyway.

Arguments:
    0: <CONTROL> Map control, supplied by the Draw event handler

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_refreshInfluenceZones
    A3A_influenceSides, A3A_influenceShapes, A3A_influencePlayerColour
                                              (set by A3A_fnc_computeInfluenceZones)
    A3A_CHAOS_influenceOverlayEnabled, A3A_CHAOS_influenceShowClaimAreas,
    A3A_CHAOS_influenceThickness, A3A_CHAOS_influenceFill,
    A3A_CHAOS_influenceFillOpacity            (CBA settings)
*/

#define BORDER_ALPHA 0.8
#define CLAIM_ALPHA  0.45
#define LINE_BUDGET  24000
#define SUPPLY_ALPHA 0.9
#define SUPPLY_DASH  600

params ["_map"];

// Read per-frame with a nil-safe default so toggling in Addon Options takes
// effect on the next frame without reopening the map.
if !(missionNamespace getVariable ["A3A_CHAOS_influenceOverlayEnabled", true]) exitWith {};

[] call A3A_fnc_refreshInfluenceZones;

private _sides = missionNamespace getVariable ["A3A_influenceSides", []];

// ---- Visible world rectangle, and metres per screen pixel ---------------
// Same idiom as fn_mapDrawOutpostsEH for the rectangle; the pixel size falls
// out of the same two corners.
private _mapPos   = ctrlMapPosition _map;
private _topLeft  = _map ctrlMapScreenToWorld [_mapPos # 0, _mapPos # 1];
private _botRight = _map ctrlMapScreenToWorld [(_mapPos # 0) + (_mapPos # 2), (_mapPos # 1) + (_mapPos # 3)];
private _viewMinX = (_topLeft # 0) min (_botRight # 0);
private _viewMaxX = (_topLeft # 0) max (_botRight # 0);
private _viewMinY = (_topLeft # 1) min (_botRight # 1);
private _viewMaxY = (_topLeft # 1) max (_botRight # 1);

private _pixelsAcross = (getResolution # 0) * (_mapPos # 2);
private _metresPerPixel = 1;
if (_pixelsAcross > 0) then { _metresPerPixel = (_viewMaxX - _viewMinX) / _pixelsAcross };
if (_metresPerPixel <= 0) then { _metresPerPixel = 1 };

// ---- Thickness ----------------------------------------------------------
private _thickness = missionNamespace getVariable ["A3A_CHAOS_influenceThickness", 4];
if !(_thickness isEqualType 0) then { _thickness = 4 };
_thickness = ((round _thickness) max 1) min 8;

private _segTotal = 0;
{ _segTotal = _segTotal + count (_x # 1) } forEach _sides;
if (_segTotal * _thickness > LINE_BUDGET) then {
    _thickness = ((floor (LINE_BUDGET / (_segTotal max 1))) max 1) min _thickness;
};

// Offsets in metres, centred on the true contour so the band straddles it.
private _offsets = [];
private _half = (_thickness - 1) / 2;
for "_t" from 0 to (_thickness - 1) do { _offsets pushBack ((_t - _half) * _metresPerPixel) };

// ---- Fill, underneath everything ---------------------------------------
if (missionNamespace getVariable ["A3A_CHAOS_influenceFill", false]) then {
    private _opacity = missionNamespace getVariable ["A3A_CHAOS_influenceFillOpacity", 0.25];
    if !(_opacity isEqualType 0) then { _opacity = 0.25 };
    _opacity = (_opacity max 0.02) min 0.8;
    {
        _x params ["_rgb", "", "_tris"];
        if (_tris isNotEqualTo []) then {
            // Opaque white procedural texture: makes drawTriangle fill with the
            // colour argument instead of only outlining it.
            _map drawTriangle [_tris, _rgb + [_opacity], "#(rgb,1,1,1)color(1,1,1,1)"];
        };
    } forEach _sides;
};

// ---- Borders ------------------------------------------------------------
{
    _x params ["_rgb", "_segments"];
    private _colour = _rgb + [BORDER_ALPHA];
    {
        _x params ["_from", "_to", "_normX", "_normY"];
        private _ax = _from # 0;
        private _bx = _to # 0;
        private _ay = _from # 1;
        private _by = _to # 1;
        if ((_ax min _bx) <= _viewMaxX
            && {(_ax max _bx) >= _viewMinX}
            && {(_ay min _by) <= _viewMaxY}
            && {(_ay max _by) >= _viewMinY}) then {
            {
                private _dx = _normX * _x;
                private _dy = _normY * _x;
                _map drawLine [[_ax + _dx, _ay + _dy], [_bx + _dx, _by + _dy], _colour];
            } forEach _offsets;
        };
    } forEach _segments;
} forEach _sides;

// ---- Claim areas --------------------------------------------------------
if (missionNamespace getVariable ["A3A_CHAOS_influenceShowClaimAreas", true]) then {
    private _claimCol = (missionNamespace getVariable ["A3A_influencePlayerColour", [0,0.5,0]]) + [CLAIM_ALPHA];
    {
        _x params ["_pos", "_semiA", "_semiB", "_angle", "_isRect"];
        // Rotated shapes never reach further than their diagonal from the centre
        private _reach = sqrt ((_semiA * _semiA) + (_semiB * _semiB));
        if ((_pos # 0) - _reach <= _viewMaxX
            && {(_pos # 0) + _reach >= _viewMinX}
            && {(_pos # 1) - _reach <= _viewMaxY}
            && {(_pos # 1) + _reach >= _viewMinY}) then {
            if (_isRect) then {
                _map drawRectangle [_pos, _semiA, _semiB, _angle, _claimCol, ""];
            } else {
                _map drawEllipse [_pos, _semiA, _semiB, _angle, _claimCol, ""];
            };
        };
    } forEach (missionNamespace getVariable ["A3A_influenceShapes", []]);
};


// ---- Supply edges -------------------------------------------------------
// The drawn border is a contour of a field rasterised on a 150-370 m grid, so
// it can only ever be an approximation of where a corridor actually runs. The
// supply edges are the authority: the server built them in
// A3A_fnc_computeSupplyGraph by sampling the same field along each corridor,
// and they are drawn here as literal lines between markers. So the border tells
// the player WHY territory connects, and these lines tell them WHAT is actually
// connected - which is the pair of jobs one coarse contour cannot do alone.
//
// Player-faction edges only: the server does not publish enemy connectivity,
// because handing every client a live map of the enemy supply network with no
// scouting is a design decision nobody has made yet.
if (missionNamespace getVariable ["A3A_CHAOS_supplyShowEdges", true]) then {
    private _edges = missionNamespace getVariable ["A3A_supplyEdges", []];
    if (_edges isNotEqualTo []) then {
        private _supplyCol = (missionNamespace getVariable ["A3A_influencePlayerColour", [0,0.5,0]]) + [SUPPLY_ALPHA];
        {
            _x params ["_mrkA", "_mrkB"];
            private _a = getMarkerPos _mrkA;
            private _b = getMarkerPos _mrkB;
            private _ax = _a # 0;
            private _ay = _a # 1;
            private _bx = _b # 0;
            private _by = _b # 1;
            if ((_ax min _bx) <= _viewMaxX
                && {(_ax max _bx) >= _viewMinX}
                && {(_ay min _by) <= _viewMaxY}
                && {(_ay max _by) >= _viewMinY}) then {
                // Dashed, so a supply line never reads as a border segment. The
                // dash length is in world metres rather than pixels, which keeps
                // the count bounded when the player zooms out: a long edge on a
                // zoomed-out map is a handful of segments, not hundreds.
                private _len = sqrt (((_bx - _ax) ^ 2) + ((_by - _ay) ^ 2));
                private _steps = (ceil (_len / SUPPLY_DASH)) max 1 min 40;
                private _ux = (_bx - _ax) / _steps;
                private _uy = (_by - _ay) / _steps;
                for "_i" from 0 to (_steps - 1) do {
                    private _x0 = _ax + _ux * _i;
                    private _y0 = _ay + _uy * _i;
                    _map drawLine [
                        [_x0, _y0],
                        [_x0 + _ux * 0.6, _y0 + _uy * 0.6],
                        _supplyCol
                    ];
                };
            };
        } forEach _edges;
    };
};
