# Style and structure

Distilled from the BI wiki *Code Best Practices* page, with this repository's conventions applied.
The overriding rule is **consistency**: match the file you are editing.

## Formatting

- 4 spaces per indent level (the codebase uses spaces; do not mix tabs in).
- Opening brace on the same line as the keyword, closing brace on its own line:
  `if (_cond) then {` … `};`
- Space is free — use blank lines to separate logical blocks, spaces around operators and after
  commas. Readability beats compactness.
- Do not one-line multi-statement logic to save a line; the memory saving is nil and the reading
  cost is real.
- `0 = someCommand` was a workaround for old editor fields. Never write it in a script file.
- Lines over ~120 characters usually want an intermediate variable, not a wrap.

## Naming

- `camelCase` for variables and functions; names must carry meaning. `_uniform`, not `_u`.
  `_i` is acceptable as a loop index.
- Constants are `UPPERCASE_WITH_UNDERSCORES` via `#define` (no trailing `;` on a `#define`).
- Everything global carries the project tag: `A3A_…` / the `GVAR` macro family. This includes
  `setVariable` keys — `player setVariable ["A3A_moneyInPocket", 250, true]`, never
  `["MoneyInPocket", …]`, which collides with other mods.
- Never use a bare `_x`, `_y`, `_forEachIndex`, `_this` as your own variable.

## Structure

- **DRY**: the same block written twice with different values is a function with parameters.
- **Flatten**: deep `if` nesting ("hadouken code") becomes guard clauses.

```sqf
if (!_cond1) exitWith { /* failure 1 */ };
if (!_cond2) exitWith { /* failure 2 */ };
if (!_cond3) exitWith { /* failure 3 */ };
// main path, unindented
```

- Long `if / else if` chains over one value become a `switch`, or `switch (true) do { case (…): … }`
  for range tests:

```sqf
private _dmg = damage player;
switch (true) do {
    case (_dmg >= 0.9): { hint "very damaged" };
    case (_dmg >= 0.5): { hint "quite damaged" };
    case (_dmg > 0):    { hint "slightly damaged" };
    default             { hint "pristine" };
};
```

- A function that no longer fits on a screen or two wants splitting.
- **Do not use macros as functions.** Macros are for constants, paths, names and logging; logic
  belongs in a function. (The existing `Faction(…)` / log macros are the sanctioned exceptions.)
- Constants: hard-coded numbers used more than once become a `#define` at the top of the file, or a
  setting if a server admin might want to tune them.

## Comments and headers

- Comments explain **why**, not what. Good names and structure carry the "what".
- Every function starts with the header block (maintainer, description, arguments with types,
  return value, scope, environment, public) — see the `antistasi-codebase` skill.
- Document locality and environment assumptions explicitly; they are invisible in the code and are
  the first thing the next reader needs.
- No commented-out code and no dead branches in a commit. Git remembers.

## Conditions

```sqf
if (_flag) then { … };            // not: if (_flag == true)
if (!_flag) then { … };           // not: if (_flag == false)
if (_a && {_b} && {_c}) then …    // lazy: only evaluate what is needed and safe
```

`if (cond == true)` is slower, longer and no clearer. Lazy `&& { … }` is also a correctness tool:
it is how you avoid evaluating `alive _x` on something you have not yet proven non-null.
