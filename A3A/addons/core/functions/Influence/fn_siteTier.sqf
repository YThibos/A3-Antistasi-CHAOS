#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    The CHAOS upgrade tier of one site, and what that tier is worth.

    Reads the published A3A_siteTiers map, so it is cheap and safe to call from
    anywhere on any machine. A marker that is not a rebel-held resource or
    factory, or that has nothing built on it, is Tier 0.

    ---- The multipliers ----------------------------------------------------
    fn_resourcecheck already splits the economy the way the tier ladder wants:
    resources are the ADDITIVE cash term and factories the MULTIPLIER. Tier
    therefore scales whichever term the site already contributes to - it never
    introduces a new term, and Tier 0 is exactly 1.0, so an un-upgraded site
    pays precisely what it paid before any of this existed.

        Tier 0   1.00    vanilla
        Tier 1   1.25    supply warehouse
        Tier 2   1.60    warehouse + power generator

    These compound across the two terms, because factories multiply the sum the
    resources add to. A map upgraded to Tier 2 everywhere is therefore worth
    roughly 1.6 x 1.6 ~ 2.6x, not 1.6x. That is the intended ceiling; anything
    beyond it needs the normalisation in fn_initZones revisited first
    (A3A_rebelCashResMult and A3A_rebelCashFactMult are computed once, from the
    map's marker counts, so they do not absorb a change here).

    Kept as constants rather than CBA settings on purpose - these are balance
    numbers to be tuned in code while the ladder is young, not knobs to hand to
    a server admin before anyone knows what good values are.

Arguments:
    0: <STRING> Marker name.

Return Value:
    <ARRAY> [_tier, _multiplier]
        _tier       <NUMBER> 0, 1 or 2
        _multiplier <NUMBER> the income multiplier for that tier

Scope: Anywhere
Environment: Unscheduled
Public: Yes
Dependencies:
    A3A_siteTiers (public, written by A3A_fnc_siteTiers)
*/

params [["_marker", "", [""]]];

private _tiers = missionNamespace getVariable ["A3A_siteTiers", createHashMap];
if !(_tiers isEqualType createHashMap) exitWith { [0, 1] };

private _tier = _tiers getOrDefault [_marker, 0];
if !(_tier isEqualType 0) then { _tier = 0 };
_tier = (round _tier) max 0 min 2;

[_tier, [1, 1.25, 1.6] select _tier]
