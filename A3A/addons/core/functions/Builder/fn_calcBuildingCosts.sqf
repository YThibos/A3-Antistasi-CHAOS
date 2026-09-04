params ["_marker"];
private _garrison = A3A_garrison get _marker;
// A marker with no garrison record yet (a site captured this frame, or a marker
// added mid-campaign) costs nothing rather than throwing on the getOrDefault.
if (isNil "_garrison") exitWith { 0 };
private _buildings = _garrison getOrDefault ["buildings", []];
private _total = 0;
{
    private _type = _x#0;
    private _price = A3A_buildingPriceHM getOrDefault [_type, 0];
    _total = _total + _price;
} forEach _buildings;
_total;