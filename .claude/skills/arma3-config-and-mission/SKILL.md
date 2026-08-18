---
name: arma3-config-and-mission
description: Arma 3 config and mission-building knowledge - config.cpp/CfgPatches/CfgVehicles class syntax and inheritance, addon packaging, mission file structure and init order, event handlers, CBA/ACE integration points. Load before editing any .cpp/.hpp config, adding a class or an addon, or reasoning about what runs at mission start.
---

# Arma 3 config and mission building

## Config language (`config.cpp`, `*.hpp`)

Config is **not** SQF. It is a class/attribute language processed by the same preprocessor.

```cpp
class CfgPatches {
    class A3A_mycomponent {
        name = "Antistasi CHAOS - my component";
        units[] = {};                       // CfgVehicles classes this addon adds to the editor
        weapons[] = {};
        requiredVersion = 2.14;
        requiredAddons[] = {"A3A_core"};    // also defines load order
        author = "…";
    };
};

class CfgVehicles {
    class B_Soldier_F;                      // external/forward declaration: no body, no members
    class A3A_MySoldier : B_Soldier_F {     // inheritance
        displayName = $STR_A3A_mysoldier;   // stringtable reference
        scope = 2;                          // 0 private, 1 protected (not in editor), 2 public
        uniformClass = "U_B_CombatUniform_mcam";
        magazines[] = {"30Rnd_65x39_caseless_mag", "30Rnd_65x39_caseless_mag"};
    };
};
```

Rules that bite:

- Every attribute line ends with `;`. Arrays use `name[] = { … };` — the `[]` is mandatory.
- Strings are double-quoted; escape by doubling (`""`).
- A base class must be declared (even empty, `class B_Soldier_F;`) before you inherit from it, and
  the addon that really defines it must be in `requiredAddons[]`.
- `scope = 2` to appear in the editor/Zeus, `scope = 1` for spawn-only, `scope = 0` to hide.
- `delete <class>;` removes an inherited member. Redefining a class in the same scope merges into
  it — that is how config patching works.
- Numbers vs strings matter: `displayName = "x";`, `cost = 100;`, and `$STR_…` (no quotes) for a
  stringtable reference inside config.
- Only the preprocessor runs here: `#define`, `#include`, `#ifdef`, macros. There are no
  expressions — `cost = 5 * 2;` is invalid.
- `__has_include` guards optional includes (this repo uses it for the member list).

## Mission vs addon

This project ships as an **addon** (PBOs under `A3A/addons/`), which is why functions come from
`CfgFunctions` in `config.cpp` rather than a mission `description.ext`. Knowledge that applies to
missions is still relevant when testing or writing a scenario:

| Mission file | Runs |
|---|---|
| `description.ext` | config for the mission (CfgFunctions, params, respawn, …) |
| `init.sqf` | every machine, scheduled, at mission start (legacy; avoid) |
| `initServer.sqf` | server only |
| `initPlayerLocal.sqf` | each client, with `_this select 1 == didJIP` |
| `initPlayerServer.sqf` | server, per connecting player |

Initialisation order (mod-relevant subset): CfgPatches load → XEH/CBA `preStart` (main menu) →
mission start → `preInit` functions → object init lines and `init*.sqf` → `postInit` functions →
first frame. Do not read another component's globals during `preInit`; guard with `isNil` or defer
to `postInit`/an event.

## Event handlers

```sqf
private _id = _unit addEventHandler ["Killed", { params ["_unit", "_killer"]; … }];
_unit removeEventHandler ["Killed", _id];
addMissionEventHandler ["EntityKilled", { … }];
```

- Handler code runs **unscheduled** — no `sleep`, no `waitUntil`.
- Handlers are **local**: add them where the object is local, or on every client for client effects.
  Ownership transfer does not carry event handlers with it.
- Prefer CBA Extended Event Handlers (`class Extended_Init_EventHandlers`) for class-wide behaviour
  instead of adding handlers to every spawned object.
- Never `removeAllEventHandlers` on an object other mods may also use.
- Store handler ids if the feature can be turned off.

## CBA and ACE integration

This mod depends on CBA and supports ACE. Use them rather than reinventing:

- Scheduling: `CBA_fnc_waitAndExecute`, `CBA_fnc_waitUntilAndExecute`, `CBA_fnc_execNextFrame`,
  `CBA_fnc_addPerFrameHandler` (+ `removePerFrameHandler`).
- Events: `CBA_fnc_addEventHandler` / `CBA_fnc_globalEvent` / `CBA_fnc_serverEvent` /
  `CBA_fnc_targetEvent` — cross-machine messaging without hand-rolled `remoteExec` fan-out.
- Settings: CBA settings (`Includes/cba_settings.sqf`) for anything a server admin should tune.
- Keybinds: `CBA_fnc_addKeybind` (this repo has `keybinds.hpp` / `keybinds/`).
- ACE: check `ADDONLOADED(...)`/`isClass` before calling ACE functions, and keep ACE-only behaviour
  behind that guard so the mod still runs without it.

## Packaging

- Each addon folder needs `$PBOPREFIX$` (`x\A3A\addons\<component>`) — paths inside the game are
  built from it, which is what `QPATHTOF` expands to.
- New addon folder ⇒ new `config.cpp` with its `CfgPatches` class ⇒ add it to the build script's
  addon list and to `mod.cpp`/`mod_dev.cpp` if user-visible.
- `requiredAddons[]` is the only reliable load-order control; a missing entry produces
  intermittent "undefined base class" errors.
- Signing keys live in `A3A/Keys/`; the release build signs PBOs (`Tools/DSSignFile/`).

## Verifying config changes

Config errors surface at game start as popup errors or missing classes. Minimum verification:

- build with `build_dev.ps1` (packing fails loudly on malformed config),
- start the game with `-showScriptErrors` and check the `.rpt` for "undefined base class",
  "Cannot find class", or config parse errors,
- confirm the class actually appears where it should (editor, Zeus, arsenal, garage).

Say plainly when a config change has only been built and not seen in game.
