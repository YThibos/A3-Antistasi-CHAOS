#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Turns rebel-held factories into physical BAR building material, delivered
    into the resource depots standing inside the HQ build area.

    ---- Why factories, and why the HQ --------------------------------------
    fn_resourcecheck already splits the economy the way the fiction wants:
    resources are the ADDITIVE cash term ("the mine sells its ore") and
    factories are the MULTIPLIER ("the plant turns money into more money").
    Materials therefore come off the factories, and the mines keep paying cash
    exactly as they always did - so this adds no currency and changes no
    existing number.

    Delivery is to depots inside the HQ build radius rather than to a depot at
    each factory. That is the logistics arc the design is built around: early
    game you are mobile and own no depot at all, and committing to a fixed,
    visible HQ is what turns production into something you can actually spend.
    It also makes depot placement a decision instead of a chore.

    ---- Connectivity -------------------------------------------------------
    Only factories that are connected to the HQ through the supply graph count.
    A factory the enemy has cut off still flies your flag and still pays its
    cash multiplier - it just stops shipping, which is the whole point of the
    graph. When the graph has not been built yet (early init, or a save that
    predates it) every owned factory counts, so this can never be the reason
    production is silently zero.

    ---- Capacity -----------------------------------------------------------
    Stock is clamped per material per depot, so a single depot cannot absorb an
    entire campaign's output: more production needs more depots, which is the
    intended tier-3 sink. A depot BAR has marked as infinite (-1, its own
    convention for an unlimited source) is skipped rather than clamped - it
    needs no delivery and writing to it would turn an infinite depot finite.

    NOT VERIFIED IN GAME: BAR's own per-depot capacity variable is not read
    here, because its name is not established from the depot side of the mod's
    API - only the [transferred, crateAmount, crateCapacity, depotAmount,
    depotCapacity] return of transferDepotToCrate is. A3A_CHAOS_barDepotCap is
    this fork's own ceiling until that is confirmed; if BAR's own capacity is
    lower, BAR will simply refuse the surplus on transfer.

Arguments:
    None

Return Value:
    <NUMBER> Total material delivered across all depots and materials.

Scope: Server
Environment: Unscheduled
Public: No
Dependencies:
    factories, sidesX, destroyedSites, teamPlayer          (globals)
    A3A_hasBAR, A3A_supplyConnected                        (globals)
    A3A_CHAOS_barFactoryYield, A3A_CHAOS_barDepotCap       (CBA settings)
    A3A_fnc_hqBuildRadius, A3A_fnc_hasConstructionYard
*/

if (!isServer) exitWith {
    Error("Server-only function miscalled");
    0
};

if (!(missionNamespace getVariable ["A3A_hasBAR", false])) exitWith { 0 };

// No yard, no depots: the depot is yard-gated in fn_teamLeaderRTSPlacerDialog, so this
// is only ever a fast exit, never a silent block on production.
if (!(call A3A_fnc_hasConstructionYard)) exitWith { 0 };

private _yield = missionNamespace getVariable ["A3A_CHAOS_barFactoryYield", 200];
if !(_yield isEqualType 0) then { _yield = 200 };
if (_yield <= 0) exitWith { 0 };

private _cap = missionNamespace getVariable ["A3A_CHAOS_barDepotCap", 3000];
if !(_cap isEqualType 0 && {_cap > 0}) then { _cap = 3000 };

// ---- How many factories are actually shipping ---------------------------
private _connected = missionNamespace getVariable ["A3A_supplyConnected", []];
private _graphReady = _connected isNotEqualTo [];

private _shipping = (missionNamespace getVariable ["factories", []]) select {
    sidesX getVariable [_x, sideUnknown] isEqualTo teamPlayer
    && {!(_x in destroyedSites)}
    && {!_graphReady || {_x in _connected}}
};
if (_shipping isEqualTo []) exitWith {
    Debug("factoryDepotTick: no connected rebel factories");
    0
};

// ---- The depots that can receive it -------------------------------------
private _hqPos = getMarkerPos "Synd_HQ";
private _hqRadius = call A3A_fnc_hqBuildRadius;

private _depots = (allMissionObjects "RessourceDepot") select {
    alive _x && {(_x distance2D _hqPos) <= _hqRadius}
};
if (_depots isEqualTo []) exitWith {
    Debug_1("factoryDepotTick: %1 factories shipping but no depot at HQ", count _shipping);
    0
};

// ---- Deliver, split evenly over the four BAR materials ------------------
// Resource sub-types (a quarry feeding Sand, a foundry feeding Metal) are a
// later piece of work; until then every factory produces all four equally, so
// no material can become a hard blocker on building.
private _total = _yield * (count _shipping);
private _perDepot = _total / (count _depots);
// Floored: BAR's stock numbers are whole units of material, and a fractional
// remainder would accumulate as noise in the save file for no gain.
private _perMaterial = floor (_perDepot / 4);
if (_perMaterial <= 0) exitWith {
    Debug_2("factoryDepotTick: yield %1 spread over %2 depots rounds to nothing", _total, count _depots);
    0
};

private _delivered = 0;
{
    private _depot = _x;
    private _stocks = _depot getVariable ["BuildAndRessources_depotStocks", [0,0,0,0]];
    if !(_stocks isEqualType []) then { _stocks = [0,0,0,0] };
    if (count _stocks < 4) then { _stocks = [0,0,0,0] };

    // BAR's own convention: -1 is an infinite source. Nothing to top up, and
    // writing a finite number over it would quietly downgrade the depot. Tested
    // as "negative" rather than "equals -1" so any sentinel BAR might use is
    // caught rather than overwritten.
    if ((_stocks findIf { _x isEqualType 0 && {_x < 0} }) > -1) then { continue };

    private _new = [];
    {
        private _before = _x;
        if !(_before isEqualType 0) then { _before = 0 };
        private _after = (_before + _perMaterial) min _cap;
        if (_after < _before) then { _after = _before };   // already over cap: leave it
        _delivered = _delivered + (_after - _before);
        _new pushBack _after;
    } forEach _stocks;

    _depot setVariable ["BuildAndRessources_depotStocks", _new, true];
} forEach _depots;

Debug_3("factoryDepotTick: %1 factories -> %2 depots, %3 delivered", count _shipping, count _depots, _delivered);

_delivered
