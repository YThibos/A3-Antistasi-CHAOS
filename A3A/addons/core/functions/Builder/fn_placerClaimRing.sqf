#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the SECOND ring shown by the RTS building placer: the claim area of
    the zone the builder box is standing in, drawn around the MARKER centre.

    ---- Why there are two rings --------------------------------------------
    The placer's own ring (A3A_fnc_buildingPlacer) is centred on the build box
    and sized by A3A_fnc_hqBuildRadius. That is the ring the placement gate
    enforces - you cannot put a structure down outside it.

    What happens to the structure AFTERWARDS is decided somewhere else and from
    somewhere else. A3A_fnc_buildingComplete asks A3A_fnc_getMarkerForPos which
    marker the finished building stands in, and that test is inArea against the
    marker - i.e. centred on the MARKER, not on the box. Park the box near the
    edge of the HQ and the two areas overlap only partially: there is ground you
    are allowed to build on that no garrison will ever record, and ground the
    garrison would happily record that the placer will not let you reach.

    Drawing the claim area alongside the build ring makes that difference
    visible instead of something the player has to infer from a structure that
    quietly failed to join a garrison. Nothing here changes either rule; this
    function only creates local scenery.

    ---- Shape ---------------------------------------------------------------
    The claim shape mirrors A3A_fnc_getMarkerForPos exactly, and is derived the
    same way A3A_fnc_computeInfluenceZones derives the map overlay's claim
    shapes:
      watchpost / roadblock (outpostsFIA) : circle of A3A_fnc_garrisonVehicleRadius
                                            (their marker size is cosmetic)
      everything else                     : the marker's own size, shape and
                                            rotation, because inArea honours all three
    So a rectangular resource marker gets a rectangle, not a circle that lies
    about where the corners are.

    ---- How it is told apart from the build ring ----------------------------
    The build ring is unchanged: white 1 m spheres, continuous, all at the box's
    own height. This ring uses the same sphere prop so it reads at the same
    distance, but is amber, dashed, and settled onto the terrain. Amber is free:
    the mod's semantic colours are Guerilla green, Occupant blue and Invader red,
    and no map or 3D convention in this repo uses orange. Dashed-versus-solid is
    already this codebase's idiom for "secondary / informational" (supply spokes
    in fn_mapDrawInfluenceEH), so the two rings differ on three axes at once and
    stay distinguishable in fog, at night and for a colour-blind player.

Arguments:
    0: <ARRAY> Position of the build box (or whatever the placer is centred on)

Return Value:
    <ARRAY> The local objects created, so the caller can delete them. Empty if
            the position is in no rebel-held zone.

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    A3A_fnc_getMarkerForPos, A3A_fnc_garrisonVehicleRadius,
    sidesX, outpostsFIA, teamPlayer
*/

// One sphere per this many metres of perimeter, before dashing.
#define RING_SPACING    10
// Dash pattern: this many spheres drawn, then the same number skipped.
#define RING_DASH       3
// Hard cap on spheres per curve/edge, so a 600 m airport marker cannot flood the scene.
#define RING_STEP_CAP   48
// Amber. Not a side colour, and not used by any existing marker convention here.
#define RING_COLOUR     "#(argb,8,8,3)color(1,0.65,0.1,1,ca)"

params [["_pos", [0,0,0], [[]]]];

private _marker = [_pos] call A3A_fnc_getMarkerForPos;
if (_marker isEqualTo "") exitWith { [] };

// Only a rebel-held marker records a garrison (same test as A3A_fnc_buildingComplete),
// so only a rebel-held marker gets a ring. sideUnknown default: sidesX getVariable ""
// is nil and comparing nil to a side throws.
if !((sidesX getVariable [_marker, sideUnknown]) isEqualTo teamPlayer) exitWith { [] };

private _centre = getMarkerPos _marker;
private _semiA = 0;
private _semiB = 0;
private _angle = 0;
private _isRect = false;

if (_marker in outpostsFIA) then {
    private _radius = [_marker] call A3A_fnc_garrisonVehicleRadius;
    _semiA = _radius;
    _semiB = _radius;
} else {
    (markerSize _marker) params ["_sizeA", "_sizeB"];
    _semiA = _sizeA;
    _semiB = _sizeB;
    _angle = markerDir _marker;
    _isRect = (markerShape _marker) isEqualTo "RECTANGLE";
};

if (_semiA <= 0 || {_semiB <= 0}) exitWith { [] };

// ---- Perimeter points in the marker's own unrotated frame ------------------
private _local = [];
if (_isRect) then {
    private _corners = [[-_semiA, -_semiB], [_semiA, -_semiB], [_semiA, _semiB], [-_semiA, _semiB]];
    for "_e" from 0 to 3 do {
        (_corners # _e) params ["_x0", "_y0"];
        (_corners # ((_e + 1) % 4)) params ["_x1", "_y1"];
        private _len = sqrt (((_x1 - _x0) ^ 2) + ((_y1 - _y0) ^ 2));
        private _steps = ((ceil (_len / RING_SPACING)) max 2) min RING_STEP_CAP;
        for "_i" from 0 to (_steps - 1) do {
            private _t = _i / _steps;
            _local pushBack [_x0 + (_x1 - _x0) * _t, _y0 + (_y1 - _y0) * _t];
        };
    };
} else {
    // Ramanujan's approximation; only used to pick a step count.
    private _perim = pi * ((3 * (_semiA + _semiB)) - sqrt (((3 * _semiA) + _semiB) * (_semiA + (3 * _semiB))));
    private _steps = ((ceil (_perim / RING_SPACING)) max 12) min (RING_STEP_CAP * 4);
    for "_i" from 0 to (_steps - 1) do {
        private _t = (_i / _steps) * 360;
        _local pushBack [_semiA * (cos _t), _semiB * (sin _t)];
    };
};

// ---- Rotate into world space and place -------------------------------------
// markerDir is clockwise from north, which is the rotation inArea applies too.
private _cosD = cos _angle;
private _sinD = sin _angle;
private _cx = _centre # 0;
private _cy = _centre # 1;

private _spheres = [];
{
    if (((floor (_forEachIndex / RING_DASH)) % 2) != 0) then { continue };
    _x params ["_lx", "_ly"];
    private _wx = _cx + (_lx * _cosD) + (_ly * _sinD);
    private _wy = _cy - (_lx * _sinD) + (_ly * _cosD);

    private _piece = "Sign_Sphere100cm_F" createVehicleLocal [_wx, _wy, 0];
    // Settled onto the terrain rather than held at the box's height: this ring can
    // be 200 m across, so a single flat height would bury half of it in a hillside.
    _piece setPosATL [_wx, _wy, 0.5];
    _piece setObjectTexture [0, RING_COLOUR];
    _piece enableSimulation false;
    _spheres pushBack _piece;
} forEach _local;

Debug_3("placerClaimRing: marker %1, %2 spheres, rect %3", _marker, count _spheres, _isRect);

_spheres
