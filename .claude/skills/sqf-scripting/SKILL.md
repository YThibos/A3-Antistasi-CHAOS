---
name: sqf-scripting
description: Rules, patterns and pitfalls for writing Arma 3 SQF. Load before writing, editing or reviewing any .sqf file, or when reasoning about scheduled vs unscheduled execution, locality/remoteExec, event handlers, private scope, or SQF performance.
---

# SQF scripting

SQF is dynamically scoped, weakly typed, has no compile step the editor can lean on, and fails
at runtime by writing one line into `arma3_x64.rpt` — often long after the mistake. Write it
defensively.

## Non-negotiables

1. **Syntax-check before you claim anything works.** Every `.sqf` you touch must pass
   `pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed`. See the `sqf-syntax-check` skill.
2. **`private` on every local.** No exceptions — see [Scoping](references/scoping.md). An
   undeclared `_var` writes into the *caller's* scope and silently corrupts it.
3. **Statements end in `;`.** The single most common SQF break is a missing `;` after a `}`.
   The last statement of a code block may omit it *only* when it is the return value.
4. **`call`, not `spawn`.** Use the unscheduled environment unless you genuinely need to wait.
   See [Execution model](references/execution-model.md).
5. **Know where the code runs.** Server, every client, or the machine that owns the object?
   Getting locality wrong is the #1 source of multiplayer-only bugs. See
   [Multiplayer](references/multiplayer.md).
6. **Never assume a variable exists.** `isNil`, `getVariable [name, default]`, `param` defaults.

## Function skeleton

```sqf
#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: <name>
    Short description of what this does and any side effects.

Arguments:
    <OBJECT> Unit to process
    <NUMBER> Radius in metres

Return Value:
    <BOOL> true when the unit was processed

Scope: Server / Any / Local Arguments
Environment: Unscheduled / Scheduled
Public: No
*/

params [
    ["_unit", objNull, [objNull]],
    ["_radius", 100, [0]]
];

if (isNull _unit) exitWith {
    Error_1("processUnit: null unit passed, radius %1", _radius);
    false
};

private _nearby = _unit nearEntities ["Man", _radius];
{
    _x setVariable [QGVAR(tagged), true, true];
} forEach _nearby;

true
```

## Quick reference of the traps that bite most often

| Trap | Right way |
|---|---|
| `_a = 1` inside a function | `private _a = 1;` |
| `if (_a = 1)` | `if (_a isEqualTo 1)` / `==` |
| `}` then a new statement, no `;` | `};` |
| `};` before `else` | `if (x) then { … } else { … };` |
| `_b = _a;` then editing `_b` mutates `_a` | `private _b = +_a;` (deep copy) |
| `count _arr == 0` | `_arr isEqualTo []` |
| `_arr = _arr + [_x]` in a loop | `_arr pushBack _x;` |
| `sleep`/`waitUntil` in an event handler | `CBA_fnc_waitAndExecute` / `CBA_fnc_waitUntilAndExecute` |
| `_arr select _i` when `_i` may be out of range | `_arr param [_i, _default]` or bounds-check |
| Mutating an array while `forEach`ing it | iterate a copy, or collect and delete afterwards |
| `str` for player-facing text | localised `LSTRING`/`localize` from `stringtable.xml` |
| `hint`/`systemChat` from the server for everyone | `remoteExec` to the right targets |

## Reference material

- [Syntax and operators](references/syntax-and-operators.md) — precedence, the `};` rule, literals.
- [Scoping and variables](references/scoping.md) — dynamic scoping, `private`, `params`, namespaces.
- [Execution model](references/execution-model.md) — scheduled vs unscheduled, PFH, event-driven design.
- [Multiplayer and locality](references/multiplayer.md) — JIP, `remoteExec`, `setVariable` public, ownership.
- [Style and structure](references/style-and-structure.md) — formatting, naming, guard clauses, comments.
- [Performance](references/performance.md) — what is actually expensive, with the wiki's benchmarks.
- [Mission optimisation](references/mission-optimisation.md) — AI/object counts, polling, network load.
- [Pitfalls](references/pitfalls.md) — the long list of engine quirks and silent failures.
- [Debugging](references/debugging.md) — `.rpt`, `-showScriptErrors`, diag commands, log macros.

Read a reference file when you are about to work in that area; do not preload all of them.
