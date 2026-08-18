// expect: W003
private _n = 1;
if (_n = 2) then { hint "nope"; };
if ((_n = 3) && {alive player}) then { hint "also nope"; };
