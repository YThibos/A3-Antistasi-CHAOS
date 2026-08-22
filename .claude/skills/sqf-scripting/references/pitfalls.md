# Pitfalls: SQF's silent failures

## Parsing and syntax

- Missing `;` after `}` — the single most common break. `};` at the end of every `if`, `while`,
  `for`, `switch`, `forEach`, and every code assignment.
- `};` before `else` splits the statement: `if (…) then { … } else { … };` is one statement.
- `;` inside an array literal, `,` between statements in a code block.
- `-1` after an identifier is a subtraction, not a negative literal: `_a -1` ≠ `_a, -1`.
- Unary vs binary command precedence — parenthesise when mixing (see syntax reference).
- `#` is `select` for arrays, not a comment. Comments are `//` and `/* */`.
- A `#define` continues on the next line only with a trailing `\`; a stray trailing `\` swallows
  the next line. Preprocessor directives must start at the beginning of a line.
- After any `#include`, Antistasi files call `FIX_LINE_NUMBERS()` so `.rpt` line numbers stay real.
- **Never pass an array or code literal inline to a log macro.** `Info_N`/`Debug_N`/`Error_N` are
  preprocessor macros, and the preprocessor splits arguments on every comma that is not inside
  parentheses — it does not understand `[]` or `{}`. `Debug_2("g=%1 n=%2", [_nx, _ny], _count)` is
  counted as four arguments, so the macro is dropped from the output ("too many macro arguments")
  and the leftover `_ny], _count);` fragment fails the **whole file** to compile, taking every
  other function in it down with it. Build the array into a local and pass the local. Commas
  inside a quoted format string are safe; the preprocessor does respect string literals. Also
  match the arity exactly — `Debug_2` wants a format string plus two values, and passing one
  ("too few parameters") drops the macro just as fatally. `Tools/sqfcheck` cannot see any of this,
  because it does not run the preprocessor: only a build or the game's `.rpt` will.
  (2026-08-22: one such call in `fn_computeInfluenceZones.sqf` cost a full test session.)

## Types and values

- `nil` vs `objNull` vs `""` vs `[]` are different absences. `isNil "_v"` (string or code form)
  tests existence; `isNull` tests object/group/display nullity.
- `_x == _y` on OBJECT compares identity; on ARRAY it errors before Arma 2.00 — use `isEqualTo`.
- `str` of a float is locale-free but lossy for display; `format ["%1", _n]` for messages.
- Arrays/hashmaps assign by reference. `+` deep-copies.
- `select` out of range returns `nil` for arrays created with `[]` sizing, but errors in other
  cases — bounds check or use `param`/`getOrDefault`.
- Numbers are single-precision floats: don't compare with `==`, compare with a tolerance.
- `count` is overloaded: `count _arr`, `{cond} count _arr`, `count _config`, `count _string`.
- `_arr set [count _arr, _v]` works but `pushBack` is clearer and returns the index.

## Control flow

- `exitWith` exits **only the current scope**. Inside a `forEach`/`count` block it exits that
  iteration's scope, not the loop and not the function. To break a loop, use `findIf`, a flag,
  or restructure.
- `if (…) exitWith { _v }` inside a function returns `_v` from the function — but only if the
  `exitWith` is at function scope.
- Assigning inside a condition (`if (_a = 1)`) is legal SQF and always "true-ish" nonsense.
- Modifying an array while `forEach`ing it skips or repeats elements. Iterate a copy (`+_arr`) or
  collect indices and delete downward afterwards.
- `waitUntil` re-evaluates its code every frame *from a fresh scope*; capture state in variables
  outside it.
- `switch` `case` blocks do not break implicitly if written as `case 1;` (fall-through) — a
  `case 1: { … };` block does not fall through.

## Objects and units

- Always check `isNull`/`alive` before acting; a unit can die or be deleted between two lines of
  scheduled code, or between the event and your handler.
- `deleteVehicle` on a unit still in a group leaves the group; delete empty groups (`deleteGroup`)
  or you leak the 288-group limit per side.
- `createUnit`/`createVehicle` return before the object is fully initialised in some cases — set
  things in the same frame, and use `BIS_fnc_spawnVehicle` semantics knowingly.
- `setPos` families differ: `setPos` (ATL/ASL depending on surface), `setPosATL`, `setPosASL`,
  `setVehiclePosition` (with placement radius and "CAN_COLLIDE"). Mixing them puts things
  underground or in orbit.
- `getPos` on an object in a vehicle returns the vehicle's position; use `getPosATL vehicle _unit`
  knowingly, and `visiblePosition` for render-accurate values.
- `attachTo` freezes damage/pathing behaviour; detach before deleting.
- `addEventHandler` returns an index — store it and `removeEventHandler` when the feature is off.
  Never `removeAllEventHandlers` on shared objects: it kills other mods' handlers.

## Mission and mod integration

- Player-facing text goes through `stringtable.xml` (`localize "STR_…"`, `LSTRING`), never
  hardcoded English.
- `hint`/`systemChat`/`titleText` only affect the machine they run on.
- `addAction` is local; add it on each client that should see it, or use CBA's
  `CBA_fnc_addPlayerAction` / ACE self-interaction menu when the mission already depends on them.
- Anything that touches the UI must run where `hasInterface` is true.
- Saving: what is not in the save code does not persist. New persistent state needs an entry in
  the save/load functions, or it silently resets on reload (a recurring class of Antistasi bug).

## Debug leftovers that must not ship

- `diag_log` spam in per-frame code, `hint` debugging, `systemChat` traces, `player` references in
  server-side code (`player` is `objNull` on a dedicated server), hardcoded test coordinates,
  `allowDamage false` left on, and commented-out blocks. Use the log macros with a level instead.

## Positions

`[0,0,0]` means nothing on its own — ASL (above sea level), ATL (above terrain), AGL, and world
coordinates are different frames, and mixing them is why objects end up underground or floating.
Pick the matching getter/setter pair (`getPosATL`/`setPosATL`, `getPosASL`/`setPosASL`,
`getPosWorld`/`setPosWorld`) and state which frame a function's position argument uses in its
header. `getPos` is also the slowest of the family and its meaning depends on context.

## Redundant and misleading idioms

- `if (_cond == true)` / `if (_cond == false)` — write `if (_cond)` / `if (!_cond)`.
- `0 = someCommand` — an old editor-field workaround, meaningless (and wrong) in a script file.
- `count _arr == 0` where `_arr isEqualTo []` says it directly.
- `_x spawn _code` per unit where one call over the whole array would do.
- Macros used as functions: they hide control flow and break line numbers in errors.
