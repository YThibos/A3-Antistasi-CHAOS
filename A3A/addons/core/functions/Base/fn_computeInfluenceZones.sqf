#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Builds the cached client-side data for the zone-of-influence map overlay
    ("borders"). Pure computation: it writes globals and draws nothing.
    A3A_GUI_fnc_mapDrawInfluenceEH consumes them.

      A3A_influenceSides   - one entry per side that holds ground, in draw
                             order (enemies first, the player faction last):
                               [ [r,g,b],                       side colour
                                 [[posA, posB, nx, ny], ...],   border segments
                                 [pos, pos, pos, ...] ]         fill triangles
                             nx/ny is the segment's unit normal, precomputed so
                             the draw handler can offset copies for line width
                             without a square root per frame. The fill array is
                             a flat list of vertices in multiples of three, the
                             shape drawTriangle wants, and is empty unless the
                             fill setting is on.
      A3A_influenceShapes  - the static-attribution ("claim") area of every
                             teamPlayer-owned zone, in the marker's own shape,
                             so it matches the inArea test fn_getMarkerForPos
                             uses.
      A3A_influencePlayerColour - the player faction's [r,g,b], so the claim
                             area layer can be drawn without hunting through
                             A3A_influenceSides for the right entry.
      A3A_influenceCellSize - grid resolution actually used, for diagnostics.

    ---- The influence model -------------------------------------------------
    Every zone projects a cone of influence that is 1 at its centre and falls
    linearly to 0 at its own radius R:

        contribution(zone, p) = max(0, 1 - distance(zone, p) / R(zone))

    R comes from A3A_fnc_zoneInfluenceRadii, which scales the configured
    reference range ("Influence range") by a per-TYPE multiplier - identical
    for every side, so an enemy outpost pushes exactly as hard as a rebel one.

    On top of that, and ONLY for the Guerilla side (teamPlayer), the radius is
    multiplied by a training factor derived from skillFIA: 0.8x at skillFIA 1
    rising to 1.2x at skillFIA 20. skillFIA is the player faction's own
    training level, so it is the player faction's radii it scales; it used to
    be applied to all three sides, which meant investing in rebel training
    silently widened the Occupants' and Invaders' reach too. There is no
    equivalent enemy variable wired in here - enemy AI skill does scale with
    tierWar (fn_NATOinit), but that is unit skill, not territorial reach, and
    hooking it up is a separate balance decision.

    A side's influence at a point is the SUM of its zones' contributions, with
    a ceiling:

        influence(side, p) = saturate( sum of contributions )
        saturate(v) = v                       for v <= 1
                    = 1 + 0.05 * (1 - 1/v)    for v > 1

    The ceiling is what stops a cluster of small markers out-pushing a large
    zone: however many roadblocks are stacked on one spot, their combined
    influence can never exceed 1.05, while a single zone at its own centre is
    already 1.0. The 5% tail above the ceiling is deliberate - a hard clamp
    would make two saturated sides tie exactly over a whole region, which
    produces degenerate zero-length contour segments. With the tail the
    ordering stays strict everywhere.

    ---- Weak long reach: closing the gaps between distant holdings ---------
    One range cannot do two jobs. R decides both how hard a position pushes and
    how far its territory has to stretch to look contiguous, so on a map whose
    objectives are far apart - Altis' northwest - the range has to be cranked up
    until the gaps close, which then hands a roadblock a 1.4 km bubble in the
    dense half of the same map.

    So every zone lays a SECOND cone, much longer and very faint, on top of the
    first:

        contribution(zone, p) = max(0, 1 - d / R)
                              + W * max(0, 1 - d / (M * R))

    M is the "Territory reach" setting (A3A_CHAOS_influenceReach, 0 .. 3 in
    steps of 0.5, default 2.5) and W is a fixed weight (A3A_influenceTailWeight,
    default 0.05, see below). R is still exactly what A3A_fnc_zoneInfluenceRadii
    returned for that zone: the long cone is a MULTIPLE of that radius, never a
    second radius table, so the per-type balance and the Guerilla training
    factor carry through it unchanged. It applies to every side identically -
    same table, same M, same W - and both cones go into the same sum, so the
    ceiling above applies to the total.

    What the long cone buys, and what it costs:

      - In genuinely empty ground, where every side's real cone is 0, the faint
        cones are the only thing present, so the two nearest holdings meet on a
        line between them and the gap closes. Where that line falls does not
        depend on W at all - it cancels out of the comparison - so W tunes
        fidelity only and never moves a gap-filling border.
      - Ground more than M*R from every zone is reached by nothing and stays
        no-man's-land, which is the point: remote wilderness belongs to nobody.
      - A holding with no neighbour therefore draws its outline at M*R rather
        than R: 2 km around a watchpost at the defaults instead of 800 m. This
        setting is also what decides how big a lone holding looks.
      - On a rim where a real cone is fading out and a neighbour's faint cone is
        arriving, the neighbour takes the ground from the point where the real
        cone has dropped below the faint one. One neighbour's faint cone is at
        most W, and a real cone loses 1/R per metre, so such a rim is pulled
        inward by at most W*R - 40 m at the 800 m default, well under one grid
        cell. A border that two real presences contest does not move
        perceptibly: the same W*R bound applies to it, and there both sides
        bring faint cones that largely cancel.
      - Faint cones ADD like real ones, being in the same sum, so a cluster of
        zones stacks them. Measured over a full Altis census (295 zones, all of
        them one side, R = 800, M = 2.5, W = 0.05, sampled on a 200 m lattice)
        the largest combined faint field anywhere on the map is 0.46, at a point
        with 25 zones in range; the map-wide median is 0.12. 0.46 is what a real
        cone is worth 430 m out from an 800 m zone's centre, so the worst stack
        Altis can build erodes a rival's outer rim from 800 m to about 430 m and
        cannot touch the inner 55% of any zone. Reaching 1.0 - a zone centre -
        would take some 2.2x the densest cluster on the map, and the ceiling
        above caps the total either way, so stacked faint cones can never beat a
        saturated interior. The stack scales linearly with W, and lowering W
        does not move the gap-filling lines, so A3A_influenceTailWeight is the
        knob if an eroded rim ever shows up in play.

    M = 0 switches the long cone off completely and restores exactly the model
    above it, hard gaps and all. That is a real choice rather than a degenerate
    one, so it is also free: the faint radius is 0, the rasterised area falls
    back to R, no bounds or budget grow, and one comparison per stamped node is
    all that is left of the feature.

    ---- Tuning the ceiling and the faint cone at runtime -------------------
    The ceiling and its tail are the two numbers worth sweeping when the border
    looks wrong around clustered zones, and sweeping them by rebuilding the
    mission is painful, so both read an optional override off missionNamespace.
    They are deliberately NOT CBA settings: "influence ceiling 1.0" means
    nothing to a player and would only clutter the options UI.

        A3A_influenceCap        default 1     sane range 0.05 .. 100
        A3A_influenceCapTail    default 0.05  sane range 0    .. 1
        A3A_influenceTailWeight default 0.05  sane range 0    .. 0.5

    From the debug console (Escape -> Debug console -> Local Exec), client side,
    since the overlay is computed per client:

        A3A_influenceCap = 0.6; A3A_influenceCapTail = 0.15;
        A3A_influenceTailWeight = 0.02;
        A3A_influenceCap = nil; A3A_influenceCapTail = nil;   // back to defaults
        A3A_influenceTailWeight = nil;

    All three are folded into the staleness signature in A3A_fnc_refreshInfluenceZones,
    so a change is picked up on the next staleness check - within 2 seconds of a
    map being drawn - with no need to force a recompute. (A map has to be open:
    the refresh is driven from the map Draw EH and nothing runs while every map
    is closed.)

    Lowering the cap makes a cluster of small zones matter less relative to one
    big zone; raising it lets stacking count for more. Raising the tail widens
    the strict-ordering margin above the cap, which is what stops two saturated
    sides tying over a whole region; a tail of exactly 0 is a hard clamp and
    brings that degeneracy back, so borders can go missing where two sides
    saturate identically. Anything outside the ranges above - or a non-number,
    or NaN - is rejected and the default used, because a cap at or below zero
    would divide by zero in the saturation below.

    W is a model constant for the same reason: "faint cone weight 0.05" means
    nothing in a settings UI, while the reach it multiplies - how far territory
    stretches into empty ground - is exactly the kind of thing a player wants to
    move, which is why that one, and only that one, is a CBA setting. W = 0 is
    accepted and is a second way to switch the long cone off, this time while
    keeping its cost.

    A node belongs to the side with the strictly highest influence there. Each
    side's border is the contour of

        advantage(side, p) = influence(side, p) - max over the other sides

    at zero, extracted with marching squares. Every side is computed on the
    SAME grid and the whole map is contoured in a single cell pass, because the
    owner of a node fixes the sign of the advantage for every side at once: a
    cell whose four corners share one owner cannot contain any side's border
    and is skipped after four array reads.

    Three sides are handled, not two, and a configuration with no Invaders (or
    any other side arrangement) needs no special case: sides are collected from
    the zones that actually exist, so a side holding no ground never appears.

    Marching squares was chosen over a hull or a union-of-discs construction
    because it needs no geometric predicates: disjoint territory yields several
    outlines, enclosed enemies yield inner outlines, and 0/1/2 zones, collinear
    zones, duplicated positions and separate landmasses all take the same path.

    Cost is bounded, not capped: the grid cell grows until the node count and
    the rasterisation work fit fixed budgets, so a late-game map degrades to a
    coarser outline instead of switching the feature off. Measured against an
    Altis-sized census, the three-side pass costs 0.86x-1.08x the old two-side
    one at the same resolution.

    The long cone is paid for in resolution, not in time. Its support is M*R, so
    it widens the bounds and multiplies each zone's rasterised area by M^2, and
    the budgets below - deliberately left exactly as they were - answer that by
    growing the cell. Simulating section 4's own loop over the Altis census at
    R = 800 and M = 2.5: at campaign start (84 sites plus ~60 towns) the cell
    goes from 151 m to 288 m, and on a fully built-out late-game map (~295
    zones) from 151 m to 373 m, in each case with the node count FALLING (28k to
    11k, 28k to 7k) because the grid coarsens faster than the bounds widen. So
    the outline gets blockier - a 373 m cell on Altis is a fifth of a grid
    square - while the work per recompute stays inside the same budget. M = 2.0
    costs about one growth step less (211 m at start, 357 m late) and M = 1.5
    close to none early on (157 m at start, 265 m late), which is the trade if
    a coarse outline is the more offensive of the two.

Arguments:
    None

Return Value:
    None

Scope: Client
Environment: Unscheduled
Public: No
Dependencies:
    markersX, outpostsFIA, controlsX, sidesX, teamPlayer, Occupants, Invaders,
    colorTeamPlayer, colorOccupants, colorInvaders, skillFIA  (public globals)
    A3A_CHAOS_influenceRange, A3A_CHAOS_influenceFill,
    A3A_CHAOS_influenceReach                                  (CBA settings)
    A3A_influenceCap, A3A_influenceCapTail,
    A3A_influenceTailWeight                                   (optional tuning
                                                               overrides, see above)
    A3A_fnc_zoneInfluenceRadii, A3A_fnc_garrisonVehicleRadius
*/

if (isNil "markersX" || {isNil "outpostsFIA"} || {isNil "sidesX"}) exitWith {
    Debug("computeInfluenceZones: zone globals not ready yet - skipping");
    A3A_influenceSides = [];
    A3A_influenceShapes = [];
};

// ---- 0. Tunables --------------------------------------------------------
private _cellMin     = 60;         // metres, finest grid resolution
private _gridSpanMax = 180;        // target grid nodes along the longest axis
private _nodeBudget  = 36000;      // ceiling on total grid nodes
private _stampBudget = 80000;      // ceiling on node writes during rasterisation
private _empty       = -1e-4;      // advantage at nodes no side reaches. Small and
                                   // negative rather than zero so a contour can
                                   // never land exactly on a node, which would
                                   // collapse two crossings into one point.
private _fillBudget  = 12000;      // max fill triangles per side
// The influence ceiling, its residual tail and the faint long cone's weight
// used to live here. They are runtime-tunable now and are read, with their
// defaults, in section 1.

// ---- 1. Settings and scaling --------------------------------------------
private _refRange = missionNamespace getVariable ["A3A_CHAOS_influenceRange", 800];
if !(_refRange isEqualType 0) then { _refRange = 800 };
_refRange = ((round (_refRange / 100)) * 100) max 100 min 1400;

private _doFill = missionNamespace getVariable ["A3A_CHAOS_influenceFill", false];
if !(_doFill isEqualType false) then { _doFill = false };

// How far territory reaches into empty ground, as a multiple of the influence
// range: the radius of the faint second cone documented in the header. 0 is a
// real setting and means no second cone at all, so it is tested for explicitly
// rather than falling out of the arithmetic.
// CBA sliders have no step, so - exactly as the influence range above does with
// its 100 m step - the half step lives here.
private _reach = missionNamespace getVariable ["A3A_CHAOS_influenceReach", 2.5];
if !(_reach isEqualType 0) then { _reach = 2.5 };
_reach = ((round (_reach / 0.5)) * 0.5) max 0 min 3;

// Rebel AI training, raised in HQ Management. fn_FIAskillAdd starts it at 1 and
// refuses past 20, and the HQ dialog shows it as "n / 20". Applied to the
// Guerilla side's zones only, in the collection loop below.
private _skill = missionNamespace getVariable ["skillFIA", 1];
if !(_skill isEqualType 0) then { _skill = 1 };
private _trainScale = 0.8 + 0.4 * (((_skill max 1) min 20) - 1) / 19;

private _radii = [_refRange] call A3A_fnc_zoneInfluenceRadii;
private _defaultRadius = _refRange;

// Overlap ceiling and its residual slope. Debug/tuning overrides rather than
// settings - see the header. Written in the affirmative so that a non-number,
// an out-of-range value and NaN all fall through to the default: a cap of 0 or
// less would divide by zero in the saturation in section 6.
private _cap = missionNamespace getVariable ["A3A_influenceCap", 1];
if !(_cap isEqualType 0 && {_cap >= 0.05} && {_cap <= 100}) then { _cap = 1 };
private _capTail = missionNamespace getVariable ["A3A_influenceCapTail", 0.05];
if !(_capTail isEqualType 0 && {_capTail >= 0} && {_capTail <= 1}) then { _capTail = 0.05 };

// Weight of the faint long cone. A model constant, not a setting - see the
// header for why, and for what it does to a rim where a real cone is fading out
// while a neighbour's faint one arrives.
private _tailW = missionNamespace getVariable ["A3A_influenceTailWeight", 0.05];
if !(_tailW isEqualType 0 && {_tailW >= 0} && {_tailW <= 0.5}) then { _tailW = 0.05 };

// Everything downstream asks two questions of the long cone: how far out does a
// zone still write anything (the radius multiplier, never below 1x, since the
// real cone is always stamped), and what does the faint term itself scale by.
// Zeroing the second is what makes "reach 0" cost nothing.
if (_reach <= 0 || {_tailW <= 0}) then { _reach = 0; _tailW = 0 };
private _reachMult = 1 max _reach;

// ---- 2. Collect zones per side and friendly claim shapes ----------------
private _controls = missionNamespace getVariable ["controlsX", []];
private _wpRadius = [] call A3A_fnc_garrisonVehicleRadius;   // watchpost/roadblock claim radius

private _allZones = markersX + outpostsFIA + _controls;
private _postFrom = count markersX;
private _postTo   = _postFrom + count outpostsFIA;

private _shapes    = [];     // friendly claim areas, drawn as-is
private _sideList  = [];     // SIDEs that hold ground
private _sideZones = [];     // parallel: [[x, y, radius], ...] per side

{
    private _mrk = _x;
    private _pos = getMarkerPos _mrk;
    // Markers that were never broadcast to this client report [0,0,0]
    if (_pos isEqualTo [0,0,0]) then { continue };

    private _side = sidesX getVariable [_mrk, sideUnknown];
    if (_side isEqualTo sideUnknown) then { continue };

    private _radius = _radii getOrDefault [_mrk, _defaultRadius];
    // Rebel training widens the Guerilla side's reach and nobody else's.
    if (_side isEqualTo teamPlayer) then { _radius = _radius * _trainScale };
    if (_radius <= 0) then { continue };

    private _idx = _sideList find _side;
    if (_idx < 0) then {
        _sideList pushBack _side;
        _sideZones pushBack [];
        _idx = (count _sideList) - 1;
    };
    (_sideZones select _idx) pushBack [_pos # 0, _pos # 1, _radius];

    if (_side isEqualTo teamPlayer) then {
        private _semiA = 0;
        private _semiB = 0;
        private _isRect = false;
        if (_forEachIndex >= _postFrom && {_forEachIndex < _postTo}) then {
            // Watchposts / roadblocks: fixed circular claim radius, marker size is cosmetic
            _semiA = _wpRadius;
            _semiB = _wpRadius;
        } else {
            private _size = markerSize _mrk;
            _semiA = _size # 0;
            _semiB = _size # 1;
            _isRect = (markerShape _mrk) isEqualTo "RECTANGLE";
        };
        if (_semiA > 0 && {_semiB > 0}) then {
            _shapes pushBack [_pos, _semiA, _semiB, markerDir _mrk, _isRect];
        };
    };
} forEach _allZones;

A3A_influenceShapes = _shapes;

if (_sideList isEqualTo []) exitWith {
    A3A_influenceSides = [];
    Debug("computeInfluenceZones: no owned zones - overlay cleared");
};

// Draw order: the player faction last, so its border sits on top of the others.
private _playerIdx = _sideList find teamPlayer;
if (_playerIdx >= 0 && {_playerIdx != (count _sideList) - 1}) then {
    _sideList pushBack (_sideList deleteAt _playerIdx);
    _sideZones pushBack (_sideZones deleteAt _playerIdx);
};

// ---- 3. Side colours, from the game's own marker colour config ----------
// colorTeamPlayer / colorOccupants / colorInvaders hold CfgMarkerColors class
// names ("colorGUER", "colorBLUFOR", "colorOPFOR" by default), so the overlay
// matches whatever the faction actually uses on this map and in this config.
//
// Those side classes do NOT store plain numbers. Verified against A3's own
// ui_f config: ColorWEST / ColorEAST / ColorGUER / ColorCIV / ColorUNKNOWN -
// and the colorBLUFOR / colorOPFOR / colorGUER aliases that inherit them -
// store each channel as a STRING holding an expression, so that the player's
// personal map colour preferences apply:
//     color[] = {"(profilenamespace getvariable ['Map_BLUFOR_R',0])", ... };
// Only the plain palette entries (ColorRed, ColorGreen, ...) hold numbers.
// So a channel is taken as-is when it is a number and evaluated when it is a
// string, and anything that does not resolve to a finite number falls back to
// the side's own hue - never to a single shared grey, because a grey border
// tells the player nothing, which is the whole point of the overlay.
private _sideFallback = {
    params ["_fbSide"];
    if (_fbSide isEqualTo teamPlayer) exitWith { [0, 0.5, 0] };
    if (!isNil "Occupants" && {_fbSide isEqualTo Occupants}) exitWith { [0, 0.3, 0.6] };
    if (!isNil "Invaders" && {_fbSide isEqualTo Invaders}) exitWith { [0.5, 0, 0] };
    [0.45, 0.45, 0.45]
};

// Resolves one color[] element to a channel in 0..1, or -1 when it cannot.
// try/catch covers an expression that throws; a malformed one yields nil or a
// non-number instead, which the checks below reject just the same.
private _channelValue = {
    params ["_raw"];
    if (_raw isEqualType 0) exitWith { (_raw max 0) min 1 };
    if !(_raw isEqualType "") exitWith { -1 };
    if (_raw isEqualTo "") exitWith { -1 };
    private _value = nil;
    try {
        _value = call (compile _raw);
    } catch {
        _value = nil;
    };
    if (isNil "_value") exitWith { -1 };
    if !(_value isEqualType 0) exitWith { -1 };
    if !(finite _value) exitWith { -1 };
    (_value max 0) min 1
};

private _sideColours = [];
{
    private _side = _x;
    private _colourName = call {
        if (_side isEqualTo teamPlayer) exitWith { missionNamespace getVariable ["colorTeamPlayer", "colorGUER"] };
        if (!isNil "Occupants" && {_side isEqualTo Occupants}) exitWith { missionNamespace getVariable ["colorOccupants", "colorBLUFOR"] };
        if (!isNil "Invaders" && {_side isEqualTo Invaders}) exitWith { missionNamespace getVariable ["colorInvaders", "colorOPFOR"] };
        "colorUNKNOWN"
    };
    private _rgb = [_side] call _sideFallback;
    private _cfg = getArray (configFile >> "CfgMarkerColors" >> _colourName >> "color");
    if (count _cfg >= 3) then {
        private _r = [_cfg # 0] call _channelValue;
        private _g = [_cfg # 1] call _channelValue;
        private _b = [_cfg # 2] call _channelValue;
        // An all-equal triple is a grey, whether it came from the config or
        // from a half-resolved expression. Treat it as a failed read.
        if (_r >= 0 && {_g >= 0} && {_b >= 0} && {!(_r isEqualTo _g) || {!(_g isEqualTo _b)}}) then {
            _rgb = [_r, _g, _b];
        } else {
            Debug_2("computeInfluenceZones: %1 gave no usable colour - using side fallback %2", _colourName, _rgb);
        };
    } else {
        Debug_2("computeInfluenceZones: %1 has no color[] - using side fallback %2", _colourName, _rgb);
    };
    _sideColours pushBack _rgb;
} forEach _sideList;

// The per-side rules above can only judge one side at a time, and the property
// that actually matters is that the sides are told APART. There is a real way
// to fail that with three perfectly valid reads: every side class resolves its
// channels off profileNamespace, and the config defaults behind those reads are
// [0,1,1] for BLUFOR, OPFOR and Independent alike, so a profile that never set
// its map colours hands back the same cyan three times. Two borders that close
// are as useless as two identical ones, hence a tolerance rather than an exact
// match. On any collision every side drops back to its own fallback: replacing
// only one of the pair would just trade this collision for the next one.
private _colourEps = 0.05;
private _collision = false;
private _colourCount = count _sideColours;
for "_i" from 0 to (_colourCount - 2) do {
    for "_j" from (_i + 1) to (_colourCount - 1) do {
        (_sideColours # _i) params ["_ir", "_ig", "_ib"];
        (_sideColours # _j) params ["_jr", "_jg", "_jb"];
        if (abs (_ir - _jr) <= _colourEps
            && {abs (_ig - _jg) <= _colourEps}
            && {abs (_ib - _jb) <= _colourEps}) then {
            _collision = true;
            Debug_3("computeInfluenceZones: %1 and %2 both resolved to %3 - using side fallbacks for every side", _sideList # _i, _sideList # _j, _sideColours # _i);
        };
    };
};
if (_collision) then {
    _sideColours = _sideList apply { [_x] call _sideFallback };
};

private _playerColourIdx = _sideList find teamPlayer;
A3A_influencePlayerColour = if (_playerColourIdx < 0) then { [teamPlayer] call _sideFallback } else { _sideColours select _playerColourIdx };

// ---- 4. Grid geometry ---------------------------------------------------
private _minX =  1e9;
private _maxX = -1e9;
private _minY =  1e9;
private _maxY = -1e9;
// Bounds are taken from the OUTER cone: the faint one reaches M*R, and ground
// it reaches is ground that can be claimed, so it has to be on the grid.
// _reachMult is 1 when the long cone is off, which leaves this exactly as it
// was.
{
    {
        _x params ["_px", "_py", "_r0"];
        private _r = _r0 * _reachMult;
        if (_px - _r < _minX) then { _minX = _px - _r };
        if (_px + _r > _maxX) then { _maxX = _px + _r };
        if (_py - _r < _minY) then { _minY = _py - _r };
        if (_py + _r > _maxY) then { _maxY = _py + _r };
    } forEach _x;
} forEach _sideZones;

private _spanX = _maxX - _minX;
private _spanY = _maxY - _minY;
private _cell  = ((_spanX max _spanY) / _gridSpanMax) max _cellMin;

// Margin, in cells, on every side of the measured bounds. The resolution floor
// in section 5 can grow a zone to 1.5 cells, and the long cone then takes that
// out to 1.5 * M cells, which is past the bounds above whenever a zone was
// small enough to be floored. Half a cell of slack on top, and 2 as the floor
// so that the long cone being off reproduces the old flat two cells exactly.
private _marginCells = 2 max (ceil (1.5 * _reachMult + 0.5));
private _marginNodes = 2 * _marginCells + 2;

// Grow the cell until both budgets are met. Bounded loop, never infinite.
private _fits  = false;
private _tries = 0;
while { !_fits && {_tries < 20} } do {
    _tries = _tries + 1;
    private _nodes  = ((floor (_spanX / _cell)) + _marginNodes) * ((floor (_spanY / _cell)) + _marginNodes);
    private _stamps = 0;
    {
        {
            // Same estimate as ever, measured on the outer cone: that is the box
            // section 5 actually walks.
            private _stampSpan = (2 * ((((_x # 2) max (1.5 * _cell)) * _reachMult) + 1.5 * _cell) / _cell) + 2;
            _stamps = _stamps + _stampSpan * _stampSpan;
        } forEach _x;
    } forEach _sideZones;
    if (_nodes <= _nodeBudget && {_stamps <= _stampBudget}) then { _fits = true } else { _cell = _cell * 1.3 };
};

private _ox = _minX - _marginCells * _cell;
private _oy = _minY - _marginCells * _cell;
private _nx = (floor (_spanX / _cell)) + _marginNodes;
private _ny = (floor (_spanY / _cell)) + _marginNodes;
private _nodeCount = _nx * _ny;
private _radiusFloor = 1.5 * _cell;      // a zone smaller than the grid would vanish

// ---- 5. Rasterise one influence field per side --------------------------
// Doubling fill: far cheaper than one pushBack per node on a 36k array.
private _zeroRow = [0];
while { count _zeroRow < _nodeCount } do { _zeroRow append (+_zeroRow) };
_zeroRow resize _nodeCount;

private _fields = [];
{
    private _field = +_zeroRow;
    {
        _x params ["_px", "_py", "_r0"];
        private _r  = _r0 max _radiusFloor;
        // The faint long cone, and the box that covers both cones. With the long
        // cone off _rt is 0, so its test below is never true and _ro is _r: the
        // walked box, and the arithmetic inside it, are what they always were.
        private _rt = _r * _reach;
        private _ro = _r max _rt;
        private _ro2 = _ro * _ro;
        private _i0 = ((floor ((_px - _ro - _ox) / _cell)) max 0);
        private _i1 = ((ceil  ((_px + _ro - _ox) / _cell)) min (_nx - 1));
        private _j0 = ((floor ((_py - _ro - _oy) / _cell)) max 0);
        private _j1 = ((ceil  ((_py + _ro - _oy) / _cell)) min (_ny - 1));
        for "_j" from _j0 to _j1 do {
            private _dy   = (_oy + _j * _cell) - _py;
            private _base = _j * _nx;
            for "_i" from _i0 to _i1 do {
                private _dx = (_ox + _i * _cell) - _px;
                private _d2 = _dx * _dx + _dy * _dy;
                if (_d2 < _ro2) then {
                    private _d = sqrt _d2;
                    private _v = 0;
                    if (_d < _r)  then { _v = 1 - _d / _r };
                    if (_d < _rt) then { _v = _v + _tailW * (1 - _d / _rt) };
                    private _idx = _base + _i;
                    _field set [_idx, (_field select _idx) + _v];
                };
            };
        };
    } forEach _x;
    _fields pushBack _field;
} forEach _sideZones;

// ---- 6. Owner and per-side advantage, in one pass -----------------------
// owner = the side index that strictly holds the node, -1 if none.
// advantage[side] > 0 exactly when owner == side, by construction.
private _sideCount = count _sideList;
private _emptyRow = [_empty];
while { count _emptyRow < _nodeCount } do { _emptyRow append (+_emptyRow) };
_emptyRow resize _nodeCount;

private _owner = +_zeroRow;
private _diffs = [];
for "_s" from 0 to (_sideCount - 1) do { _diffs pushBack (+_emptyRow) };

private _vals = [];
_vals resize _sideCount;
private _sLast = _sideCount - 1;
for "_n" from 0 to (_nodeCount - 1) do {
    private _any = false;
    for "_s" from 0 to _sLast do {
        if (((_fields select _s) select _n) > 0) exitWith { _any = true };
    };
    if (!_any) then { _owner set [_n, -1]; continue };

    private _best = 0;
    private _second = 0;
    private _bestIdx = -1;
    for "_s" from 0 to _sLast do {
        private _v = (_fields select _s) select _n;
        if (_v > _cap) then { _v = _cap + _capTail * (1 - _cap / _v) };
        _vals set [_s, _v];
        if (_v > _best) then { _second = _best; _best = _v; _bestIdx = _s }
        else { if (_v > _second) then { _second = _v } };
    };
    if (_best <= _second) then { _bestIdx = -1 };
    _owner set [_n, _bestIdx];
    for "_s" from 0 to _sLast do {
        (_diffs select _s) set [_n, (_vals select _s) - ([_best, _second] select (_s isEqualTo _bestIdx))];
    };
};

// ---- 7. One marching-squares pass for every side ------------------------
// Corner layout per cell: 00 = bottom-left, 10 = bottom-right,
// 11 = top-right, 01 = top-left. Edges are bottom, right, top, left.
private _segs  = [];
private _fills = [];
for "_s" from 0 to _sLast do { _segs pushBack []; _fills pushBack [] };

private _jLast = _ny - 2;
private _iLast = _nx - 2;
private _xRight = _ox + (_nx - 1) * _cell;

for "_j" from 0 to _jLast do {
    private _b0 = _j * _nx;
    private _b1 = _b0 + _nx;
    private _y0 = _oy + _j * _cell;
    private _y1 = _y0 + _cell;
    private _runSide = -1;
    private _runX = 0;

    for "_i" from 0 to _iLast do {
        private _o00 = _owner select (_b0 + _i);
        private _o10 = _owner select (_b0 + _i + 1);
        private _o11 = _owner select (_b1 + _i + 1);
        private _o01 = _owner select (_b1 + _i);
        private _x0 = _ox + _i * _cell;

        if (_o00 isEqualTo _o10 && {_o00 isEqualTo _o11} && {_o00 isEqualTo _o01}) then {
            // Whole cell held by one side, or by nobody: no border here.
            if (_doFill && {_o00 >= 0} && {_runSide != _o00}) then {
                if (_runSide >= 0) then {
                    (_fills select _runSide) append [[_runX,_y0],[_x0,_y0],[_x0,_y1],[_runX,_y0],[_x0,_y1],[_runX,_y1]];
                };
                _runSide = _o00;
                _runX = _x0;
            };
            continue;
        };
        if (_doFill && {_runSide >= 0}) then {
            (_fills select _runSide) append [[_runX,_y0],[_x0,_y0],[_x0,_y1],[_runX,_y0],[_x0,_y1],[_runX,_y1]];
            _runSide = -1;
        };
        if (_o00 < 0 && {_o10 < 0} && {_o11 < 0} && {_o01 < 0}) then { continue };

        private _x1 = _x0 + _cell;
        private _p00 = [_x0,_y0];
        private _p10 = [_x1,_y0];
        private _p11 = [_x1,_y1];
        private _p01 = [_x0,_y1];

        private _todo = [];
        if (_o00 >= 0) then { _todo pushBackUnique _o00 };
        if (_o10 >= 0) then { _todo pushBackUnique _o10 };
        if (_o11 >= 0) then { _todo pushBackUnique _o11 };
        if (_o01 >= 0) then { _todo pushBackUnique _o01 };

        {
            private _k = _x;
            private _d = _diffs select _k;
            private _v00 = _d select (_b0 + _i);
            private _v10 = _d select (_b0 + _i + 1);
            private _v11 = _d select (_b1 + _i + 1);
            private _v01 = _d select (_b1 + _i);
            private _s00 = _o00 isEqualTo _k;
            private _s10 = _o10 isEqualTo _k;
            private _s11 = _o11 isEqualTo _k;
            private _s01 = _o01 isEqualTo _k;

            private _edgeB = [];
            private _edgeR = [];
            private _edgeT = [];
            private _edgeL = [];
            private _crossings = [];
            if !(_s00 isEqualTo _s10) then {
                _edgeB = [_x0 + _cell * (_v00 / (_v00 - _v10)), _y0];
                _crossings pushBack _edgeB;
            };
            if !(_s10 isEqualTo _s11) then {
                _edgeR = [_x1, _y0 + _cell * (_v10 / (_v10 - _v11))];
                _crossings pushBack _edgeR;
            };
            if !(_s01 isEqualTo _s11) then {
                _edgeT = [_x0 + _cell * (_v01 / (_v01 - _v11)), _y1];
                _crossings pushBack _edgeT;
            };
            if !(_s00 isEqualTo _s01) then {
                _edgeL = [_x0, _y0 + _cell * (_v00 / (_v00 - _v01))];
                _crossings pushBack _edgeL;
            };

            private _avg = (_v00 + _v10 + _v11 + _v01) / 4;
            private _segList = _segs select _k;
            // Zero-length segments happen when two sides tie exactly on a node.
            // They cannot be drawn and have no direction, so drop them.
            private _fnc_push = {
                params ["_a", "_b"];
                private _ddx = (_b # 0) - (_a # 0);
                private _ddy = (_b # 1) - (_a # 1);
                private _len = sqrt (_ddx * _ddx + _ddy * _ddy);
                if (_len > 1e-4) then { _segList pushBack [_a, _b, _ddy / _len, - _ddx / _len] };
            };

            if (count _crossings == 2) then {
                [_crossings # 0, _crossings # 1] call _fnc_push;
            } else {
                // Saddle. The positive region is connected exactly when the cell
                // average is positive; resolve both the contour and the fill from
                // that one test so the two cannot disagree.
                if (_s00 isEqualTo (_avg > 0)) then {
                    [_edgeB, _edgeR] call _fnc_push;
                    [_edgeT, _edgeL] call _fnc_push;
                } else {
                    [_edgeL, _edgeB] call _fnc_push;
                    [_edgeR, _edgeT] call _fnc_push;
                };
            };

            if (_doFill && {count (_fills select _k) < 3 * _fillBudget}) then {
                // The part of this cell that belongs to side _k, as a polygon,
                // fanned into triangles from its first vertex. Verified
                // exhaustively: this polygon plus the one for the complement
                // always add up to exactly one cell.
                private _cnt = ([0,1] select _s00) + ([0,1] select _s10) + ([0,1] select _s11) + ([0,1] select _s01);
                private _poly = [];
                switch (_cnt) do {
                    case 1: {
                        if (_s00) then { _poly = [_p00, _edgeB, _edgeL] }
                        else { if (_s10) then { _poly = [_p10, _edgeR, _edgeB] }
                        else { if (_s11) then { _poly = [_p11, _edgeT, _edgeR] }
                        else { _poly = [_p01, _edgeL, _edgeT] } } };
                    };
                    case 3: {
                        if (!_s00) then { _poly = [_edgeB, _p10, _p11, _p01, _edgeL] }
                        else { if (!_s10) then { _poly = [_p00, _edgeB, _edgeR, _p11, _p01] }
                        else { if (!_s11) then { _poly = [_p00, _p10, _edgeR, _edgeT, _p01] }
                        else { _poly = [_p00, _p10, _p11, _edgeT, _edgeL] } } };
                    };
                    case 2: {
                        if (_s00 && _s10) then { _poly = [_p00, _p10, _edgeR, _edgeL] }
                        else { if (_s10 && _s11) then { _poly = [_edgeB, _p10, _p11, _edgeT] }
                        else { if (_s11 && _s01) then { _poly = [_edgeL, _edgeR, _p11, _p01] }
                        else { if (_s01 && _s00) then { _poly = [_p00, _edgeB, _edgeT, _p01] }
                        else {
                            // Saddle: the two corners are diagonally opposite.
                            if (_s00) then {
                                if (_avg > 0) then { _poly = [_p00, _edgeB, _edgeR, _p11, _edgeT, _edgeL] }
                                else { (_fills select _k) append [_p00,_edgeB,_edgeL,_p11,_edgeT,_edgeR] };
                            } else {
                                if (_avg > 0) then { _poly = [_edgeB, _p10, _edgeR, _edgeT, _p01, _edgeL] }
                                else { (_fills select _k) append [_p10,_edgeR,_edgeB,_p01,_edgeL,_edgeT] };
                            };
                        } } } };
                    };
                    default {};
                };
                private _polyCount = count _poly;
                if (_polyCount >= 3) then {
                    private _first = _poly # 0;
                    for "_t" from 1 to (_polyCount - 2) do {
                        (_fills select _k) append [_first, _poly # _t, _poly # (_t + 1)];
                    };
                };
            };
        } forEach _todo;
    };

    if (_doFill && {_runSide >= 0}) then {
        (_fills select _runSide) append [[_runX,_y0],[_xRight,_y0],[_xRight,_y1],[_runX,_y0],[_xRight,_y1],[_runX,_y1]];
    };
};

// ---- 8. Publish the cache -----------------------------------------------
private _out = [];
for "_s" from 0 to _sLast do {
    _out pushBack [_sideColours select _s, _segs select _s, _fills select _s];
};
A3A_influenceSides = _out;
A3A_influenceCellSize = _cell;

// Debug_8 is the widest logging macro there is, so the grid and the side count
// travel as one array rather than losing a field.
Debug_8("computeInfluenceZones: range=%1m reach=%2x/%3 train=%4 cap=%5/%6 cell=%7m [nx,ny,sides]=%8",
    _refRange, _reach, _tailW, _trainScale, _cap, _capTail, round _cell, [_nx, _ny, _sideCount]);
