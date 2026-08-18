# SQF syntax and operators

## Statements

- A script is a sequence of statements separated by `;`.
- The value of the **last** statement of a code block is its return value. That last statement is
  the only one that may drop its `;`. Anything after it (even a comment-free blank line) is fine,
  but another statement makes the earlier one's value irrelevant.
- `{ … }` does not execute anything: it *creates* a value of type CODE. It runs when something
  calls it (`call`, `spawn`, `then`, `do`, `forEach`, `count`, `apply`, …).
- Because `{ … }` is a value, it must be terminated like any other value:

```sqf
if (_x) then { … };          // correct
private _f = { … };          // correct
{ … } forEach _arr;          // correct
if (_x) then { … }           // WRONG when another statement follows
hint "next";
```

## Operator precedence (practical version)

From tightest to loosest:

1. Unary operators and **unary commands**: `-x`, `!x`, `count _arr`, `str _x`, `alive _x`.
2. `#` (select), `^`
3. `*`, `/`, `%`, `mod`, `atan2`, `min`, `max`
4. `+`, `-`
5. `==`, `!=`, `<`, `>`, `<=`, `>=`, `>>`
6. `&&`/`and`, `||`/`or`
7. **Binary commands** (`setPos`, `getVariable`, `isEqualTo`, `call`, `select`, …) all sit at the
   same level and evaluate **left to right**.
8. `=` (assignment) — a grammar rule, not an operator. There is no `+=`, `++`, `?:`.

Consequences worth internalising:

```sqf
count units player > 3           // parses as count (units player) > 3   -- fine
_a select 0 + 1                  // (_a select 0) + 1?  NO: binary cmds are left-to-right,
                                 // but + binds tighter, so it is _a select (0 + 1)
!alive _x && _y                  // (!alive _x) && _y
!(alive _x && _y)                // what you probably meant
_unit distance _pos < 50         // fine: comparison is looser than the binary command
```

**Rule of thumb: parenthesise anything mixing a binary command with arithmetic or comparison.**
Extra parentheses cost nothing measurable; a mis-parse costs an evening.

## Lazy evaluation

`&&` and `||` short-circuit only when the right-hand side is CODE:

```sqf
if (!isNull _veh && {alive _veh}) then { … };   // safe: braces defer the second test
if (!isNull _veh && alive _veh) then { … };     // both sides evaluated, may throw
```

Use `&& { … }` whenever the second condition is only valid if the first one held.

## Literals and types

- Numbers: `1`, `1.5`, `1e3`, `0xFF`. `-1` after an identifier is a subtraction — `_a -1` is
  `_a - 1`, not the array `[-1]`.
- Strings: `"double"` or `'single'`. Escape by doubling the same quote: `"say ""hi"""`.
- Arrays: `[1, 2, 3]` — elements separated by `,`, never `;`.
- Booleans: `true` / `false`. `nil` is the absence of a value; `objNull`, `grpNull`, `locationNull`,
  `controlNull`, `scriptNull`, `[]`, `""`, `createHashMap` are the empty values of their types.
- Arrays and hashmaps are **reference** types. `private _b = _a;` aliases; `private _b = +_a;`
  deep-copies. Hashmaps: `+_map` also deep-copies.

## Control flow

```sqf
if (_cond) then { … } else { … };
if (_cond) exitWith { _returnValue };            // exits the *current scope*, not the script
private _r = if (_cond) then [{ … }, { … }];     // array form returns a value

for "_i" from 0 to 9 do { … };
for "_i" from (count _a - 1) to 0 step -1 do { … };   // safe deletion order
{ … } forEach _arr;                              // _x, _forEachIndex are provided
while {_cond} do { … };                          // condition is CODE
switch (_x) do { case 1: { … }; case 2; case 3: { … }; default { … }; };

private _n = { alive _x } count _units;          // counts matching elements
private _first = _units findIf { !alive _x };    // index or -1
private _hit = _units select { alive _x };       // filtered array
private _new = _units apply { name _x };         // mapped array
```

Note `case 2;` (no colon-block) falls through to the next case's block; `default` takes no colon.

## Error handling

```sqf
try {
    if (_bad) throw "explanation";
} catch {
    Error_1("thing failed: %1", _exception);
};
```

`throw` only unwinds to the nearest `try`; it is not a substitute for validating inputs.
