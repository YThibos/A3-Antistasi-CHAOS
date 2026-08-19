// Reset positions of all HQ objects except petros
// Server, unscheduled

params ["_newPos"];

// Move headless client logic objects near HQ so that firedNear EH etc. work more reliably
private _hcpos = _newPos vectorAdd [-100, -100, 0];
{ _x setPosATL _hcpos } forEach (entities "HeadlessClient_F");

private _alignNormals = {
	private _thing = _this;
	_thing setVectorUp surfaceNormal getPos _thing;
};

// WP4: capture old HQ centre before any objects are moved, for Construction Yard search
private _oldHQPos = getPos fireX;

private _firePos = [_newPos, 3, getDir petros] call BIS_Fnc_relPos;
//Extra height on the fire to avoid it clipping into the ground
fireX setPos (_firePos vectorAdd [0,0,0.1]);
_rnd = getdir petros;
_pos = [_firePos, 3, _rnd] call BIS_Fnc_relPos;
boxX setPos _pos;
_rnd = _rnd + 45;
_pos = [_firePos, 3, _rnd] call BIS_Fnc_relPos;
mapX setDir ([_firePos, _pos] call BIS_fnc_dirTo);
mapX setPos _pos;
_rnd = _rnd + 45;
_pos = [_firePos, 3, _rnd] call BIS_Fnc_relPos;
_emptyPos = _pos findEmptyPosition [0,50,(typeOf flagX)];
_pos = if (count _emptyPos > 0) then {_emptyPos} else {_pos};
flagX setPos _pos;
_rnd = _rnd + 45;
_pos = [_firePos, 3, _rnd] call BIS_Fnc_relPos;
vehicleBox setPos _pos;

//Align with ground. Deliberately ignoring flagX, because a flag pole at 45 degrees looks /weird/
{_x call _alignNormals} forEach [fireX, boxX, mapX, vehicleBox];

// WP4: move Construction Yard with HQ (follows HQ option from §6d)
private _yards = (nearestObjects [_oldHQPos, ["a3a_constructionYard"], 400]) select {
    _x getVariable ["A3A_isConstructionYard", false]
};
if (_yards isNotEqualTo []) then {
    private _yardPos = [_newPos, 20, (getDir petros + 200) % 360] call BIS_Fnc_relPos;
    (_yards#0) setPos _yardPos;
    (_yards#0) call _alignNormals;
};

boxX hideObjectGlobal false;
vehicleBox hideObjectGlobal false;
mapX hideObjectGlobal false;
fireX hideObjectGlobal false;
flagX hideObjectGlobal false;
