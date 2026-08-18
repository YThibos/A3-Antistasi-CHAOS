---
name: antistasi-codebase
description: How this Antistasi CHAOS fork is laid out - addons, CfgFunctions registration, macros, includes, logging, events, settings, stringtables and the build. Load before adding or moving a function, touching config.cpp/CfgFunctions.hpp, adding a setting or a string, or working out where an existing feature lives.
---

# Antistasi CHAOS codebase

This is a fork of Antistasi Community Edition (`unstable` branch). It ships as an **Arma 3 mod**
(`A3A/addons/*` PBOs), not a mission folder. Keep fork changes tidy and additive so upstream
`unstable` keeps merging.

## Layout

```
A3A/addons/<component>/          one PBO each: core, events, garage, gear, gui, logistics,
                                 maps, tasks, patcom, jeroen_arsenal, config_fixes
    config.cpp                   CfgPatches + includes for that component
    script_component.hpp         #define COMPONENT, then include script_mod.hpp
    CfgFunctions.hpp             the function registry for the component
    functions/<Group>/fn_*.sqf   the code
    Stringtable.xml              localised text
    Includes/                    (core only) macros: script_macros*.hpp, LogMacros.inc, common.inc
Tools/                           build, validation and helper tooling
build/, *.ps1                    build scripts; see "How to build.md"
```

`core` is the bulk of the game logic. Prefer extending the component that owns a feature over
piling more into `core`.

## Adding a function

1. Create `A3A/addons/<component>/functions/<Group>/fn_<name>.sqf`.
2. Register it in that component's `CfgFunctions.hpp`, inside the matching group class:

```cpp
class Base {
    file = QPATHTOFOLDER(functions\Base);
    class myNewThing {};                    // -> A3A_fnc_myNewThing
    class myInitThing { preInit = 1; };     // runs at preInit, every mission - use sparingly
};
```

   The class name **must** match the file name after `fn_`. A missing entry means the function
   silently does not exist; a stale entry means a startup error.
3. Call it as `[_args] call A3A_fnc_myNewThing;` — never `execVM`, never `compile` at call time.
4. Start the file with the standard include and a header:

```sqf
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: <you>
    What it does, and any side effects.

Arguments:
    <OBJECT> the unit
    <NUMBER> radius

Return Value:
    <BOOL> success

Scope: Server
Environment: Unscheduled
Public: No
*/
params [["_unit", objNull, [objNull]], ["_radius", 100, [0]]];
```

   `FIX_LINE_NUMBERS()` after every `#include` keeps `.rpt` line numbers pointing at the real file.
   The include path is relative to the file, so a function one folder deeper needs `..\..\..\`.

## Macros you will actually use

From `A3A/addons/core/Includes/` (pulled in via `script_component.hpp` / `common.inc`):

| Macro | Expands to | Use |
|---|---|---|
| `GVAR(x)` / `QGVAR(x)` | `A3A_<component>_x` / the same as a string | component-scoped globals and variable names |
| `EGVAR(comp,x)` / `QEGVAR` | another component's global | cross-component state |
| `FUNC(x)` / `EFUNC(comp,x)` | `A3A_<component>_fnc_x` | function references |
| `QPATHTOF(p)` / `QPATHTOFOLDER(p)` | full PBO path as a string | file and config paths |
| `Faction(_side)` | the faction hashmap for a side | template/faction lookups |
| `FactionGet(FAC, "key")`, `FactionGetOrDefault(FAC, "key", _def)` | faction data | template values |
| `Info_N(...)`, `Debug_N(...)`, `Error_N(...)`, `Server*` variants | level-filtered logging | **use instead of `diag_log`** |
| `FIX_LINE_NUMBERS()` | `#line` directive | after every `#include` |
| `VARDEF(v, def)` | value or default | reading a possibly-undefined global |

The `_N` suffix on the log macros is the number of format arguments: `Info_2("a %1 b %2", _x, _y)`.

## Events

`A3A/addons/events` provides a declared event bus. Events and their argument contracts live in
`A3A/addons/events/Events.hpp`; arguments are validated against it.

```sqf
["AIVehInit", [_vehicle, _side]] call A3A_fnc_triggerEvent;
private _id = ["AIVehInit", { params ["_veh", "_side"]; … }] call A3A_fnc_addEventListener;
[_id] call A3A_fnc_removeEventListener;
```

Prefer an event over polling, and declare a new event in `Events.hpp` rather than firing an
undeclared string. CBA events (`CBA_fnc_addEventHandler`) are also available for engine-level and
cross-machine signalling.

## Settings, strings and persistence

- **Settings**: mission parameters in `A3A/addons/core/Params.hpp`, client-side options in
  `clientOptions.hpp`, CBA settings in `Includes/cba_settings.sqf`. Add the setting *and* its
  stringtable entries; never read a raw magic number in the middle of game logic.
- **Text**: every player-visible string belongs in the component's `Stringtable.xml` and is used
  via `localize`/`LSTRING`. English literals in SQF do not survive review.
- **Persistence**: new campaign state must be added to the save/load path under
  `A3A/addons/core/functions/Save/` (and its version-conversion functions if the format changes).
  State that is not saved silently resets on reload — a recurring bug class in this project.

## Build and validation

- `How to build.md` documents the Arma 3 Tools / VS Code Arma Dev workflow; `build_dev.ps1` and
  `build_stable.ps1` drive local builds, `AntistasiBuilder.exe` and `Tools/Builder/` the packaged one.
- Syntax check before every commit: `pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed`
  (see the `sqf-syntax-check` skill).
- `Tools/sqfvalidator/` is the vendored Python `sqflint`, used by the upstream CI workflow; it is
  optional locally and needs Python installed.
- Test in a **dedicated local server + separate client**, not only the editor: this mission is
  multiplayer-first and hosted-host hides locality bugs.

## Fork hygiene

- Keep CHAOS-specific behaviour behind settings or clearly-scoped functions where practical.
- Prefer adding files over rewriting upstream files; when an upstream file must change, keep the
  diff minimal and local to the change.
- `WORK.md` tracks this fork's open bugs and improvement notes — read it before starting work in an
  area, and update it when a listed item is fixed.
