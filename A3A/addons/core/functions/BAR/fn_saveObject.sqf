#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    BAR Persistency hook — registered as Persistency_fnc_saveObject so that
    BuildAndRessources calls it when an object is placed.

    BAR's call site (fn_placeObject.sqf):
        if (!isNil "Persistency_fnc_saveObject") then {
            [[_previewObject]] remoteExecCall ["Persistency_fnc_saveObject", 2];
        };

    _this  = [[_placedObject]]
    params → _objects = [_placedObject]

    The live object reference is pushed into A3A_barBuiltObjects.
    fn_barSave converts the list to [class, posWorld, vectorDir, vectorUp] arrays
    at save time and filters out any null entries left by demolitions.

Arguments:
    0: <ARRAY> array of placed objects (BAR wraps a single object in two arrays)

Return Value:
    <nil>

Scope:       Server
Environment: Unscheduled (via remoteExecCall from client)
Public:      No  — BAR-internal hook only
*/
params ["_objects"];

if (!isServer) exitWith {};
if (isNil "A3A_barBuiltObjects") then { A3A_barBuiltObjects = [] };

{
    if (!isNull _x) then {
        A3A_barBuiltObjects pushBackUnique _x;
    };
} forEach _objects;

Debug_1("barSaveObject: A3A_barBuiltObjects has %1 entr(ies)", count A3A_barBuiltObjects);

