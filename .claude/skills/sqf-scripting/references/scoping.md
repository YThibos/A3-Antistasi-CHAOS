# Scoping and variables

## SQF is dynamically scoped

A CODE object has no memory of where it was written. When it runs, it sees the variables of the
**call stack that is running it**, searched from the innermost scope outward.

Scopes that stack on top of the caller's scope (the called code can read and write the caller's
locals): `call`, `if/then/else`, `switch`, `while`, `for`, `forEach`, `count`, `apply`, `select`,
`findIf`, `waitUntil`, `try/catch`, `exitWith`.

Scopes that are **isolated** (no access to the caller's locals): `spawn`, `execVM`, event handler
code, `remoteExec`'d code, `addAction` code, PFH code, `compile`d strings called from elsewhere.
Pass what they need through `_this`, or capture it explicitly.

## Therefore: `private`, always

```sqf
_total = 0;              // WRONG: writes into whichever caller scope already has _total
private _total = 0;      // right: creates it here, destroyed when this scope ends
```

Two failure modes this prevents:

```sqf
// 1. clobbering the caller's loop variable
badFn = { _x = 5; };                       // overwrites forEach's _x in the caller
{ call badFn; hint str _x; } forEach [1,2,3];

// 2. leaking a value out and getting a stale one back on the next call
```

Declaration forms:

```sqf
private _a = 1;
private ["_a", "_b"];                       // declared as nil
params ["_unit", "_pos"];                   // preferred for function arguments
params [["_unit", objNull, [objNull]], ["_n", 1, [0]]];   // default + type check
private _r = _this param [2, 5, [0]];       // single optional argument
_config params ["_name", "_cost"];          // destructure any array
```

`params` and `param` always create the variables as private in the current scope, and the type
array (`[objNull]`, `[0]`, `[""]`, `[[]]`, `[true]`, `[{}]`, `[createHashMap]`) makes a wrong
caller fail loudly at the boundary instead of ten lines deeper.

`if/then` blocks are scopes too:

```sqf
if (_c) then { private _v = 1; } else { private _v = 2; };
hint str _v;                          // undefined variable

private _v = if (_c) then {1} else {2};   // do this instead
```

## Naming

- `_camelCase` locals, descriptive: `_nearestTown`, not `_nt`.
- Never shadow the engine's magic locals: `_x`, `_y`, `_forEachIndex`, `_this`, `_exception`,
  `_thisScript`, `_thisArgs`, `_thisEventHandler`, `_fnc_scriptName`.
- Globals are a last resort. When one is unavoidable it is `A3A_<component>_<name>`, created
  through the `GVAR`/`QGVAR` macros so the prefix stays consistent.

## Namespaces instead of globals

```sqf
_unit setVariable ["A3A_state", _v];          // local to this machine
_unit setVariable ["A3A_state", _v, true];    // broadcast + JIP-persistent
_unit setVariable ["A3A_state", _v, _owner];  // send to one client/owner id
private _v = _unit getVariable ["A3A_state", 0];   // ALWAYS give a default
```

Namespaces available: `missionNamespace` (default for globals), `uiNamespace` (survives mission
restart, client only), `profileNamespace` (persists to the player profile — `saveProfileNamespace`
to flush), `serverNamespace`, plus any object/group/location/display/control/task.

Setting `nil` clears a variable: `_unit setVariable ["A3A_state", nil, true];`

## HashMaps

Prefer a `HASHMAP` over parallel arrays or "associative arrays" of pairs:

```sqf
private _m = createHashMapFromArray [["cost", 100], ["tier", 2]];
private _cost = _m getOrDefault ["cost", 0];
_m set ["tier", 3];
if ("tier" in _m) then { … };
_m deleteAt "tier";
{ /* _x = key, _y = value */ } forEach _m;
```

Keys may be STRING, NUMBER, BOOL, SIDE, ARRAY, CODE, OBJECT… but keep them stable and simple.
`+_map` copies; assignment aliases.
