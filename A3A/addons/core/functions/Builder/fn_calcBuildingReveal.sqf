// WP5c: Scale detection cap with war tier (1400 @ WT1 -> 5000 @ WT10)
// Early HQs saturate quickly (stay hidden). A WT10 HQ can fortify before saturating.
private _maxCost = 1000 + 400 * (tierWar max 1);
private _cost = ["Synd_HQ"] call A3A_fnc_calcBuildingCosts;
private _reveal = 500 + ((_cost min _maxCost) / 5);
A3A_HQDetectionRadius = _reveal;
