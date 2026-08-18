# SQF performance

Order of magnitude first: the expensive things in Arma are **config lookups, file reads, network
traffic, spawning scripts and per-frame work over big arrays**. Micro-optimising arithmetic is
noise next to those.

## The big wins

1. **Precompile.** `compile preprocessFileLineNumbers` once at init (that is what `PREP` does);
   never `execVM` or `compile` at call time. `preprocessFileLineNumbers` also gives usable line
   numbers in the `.rpt`.
2. **Unscheduled over scheduled** — roughly 7× faster, and no scheduler queue contention.
3. **Cache config reads.** `configFile >> …` walks are slow; read once at init into a hashmap or a
   variable, not per unit per frame.
4. **Cache expensive queries.** `nearestObjects`, `nearEntities`, `lineIntersects*`,
   `allUnits`/`allPlayers` filters, `selectBestPlaces`, path queries. Recompute on an event or a
   timer, not every tick.
5. **Do less per frame.** Split large jobs across PFH ticks with an index cursor.

## Array and hashmap idioms

```sqf
_arr pushBack _x;                    // not _arr = _arr + [_x]  (that copies the whole array)
_arr append _other;                  // not _arr = _arr + _other
_arr deleteAt _i;                    // O(n) but no copy; iterate downward when deleting in a loop
_arr isEqualTo [];                   // not count _arr == 0
private _n = {_cond} count _arr;     // single pass
_arr findIf {_cond} > -1;            // stops at the first hit, unlike count
_arr select {_cond};                 // filter
_arr apply {_expr};                  // map
_arr arrayIntersect _other;
private _copy = +_arr;               // deep copy when you must not alias
```

Lookups by key belong in a `HASHMAP` (`getOrDefault`, `set`, `in`, `deleteAt`), not in a linear
`findIf` over an array of pairs — hashmaps are O(1) and much faster above a handful of entries.

## Loop hygiene

```sqf
// hoist invariants out of the loop
private _pos = getPos _base;
{ if (_x distance _pos < 100) then { … }; } forEach _units;

// count/findIf/select are engine-side loops: faster than a forEach that does the same job
// avoid nested O(n²) scans over allUnits; pre-bucket by area or side instead
```

`forEach` over `allUnits` on every frame is a mission-killer; use `nearEntities` around the
relevant point, or maintain your own list updated by events.

## Cheap things people wrongly avoid

- `private`, `params` and type-checked `params` defaults: negligible cost, huge safety.
- Extra parentheses: zero cost.
- Local variables for repeated sub-expressions: strictly faster.

## Measured equivalences

From the BI wiki *Code Optimisation* benchmarks (Arma 3 v1.82; averages over 10 000 iterations).
Use these to pick between two ways of writing the same thing — not to contort readable code.

**Worth changing today**

| Slow | Fast | Why |
|---|---|---|
| `execVM "f.sqf"` (0.275 ms, empty file!) | precompiled function + `call` (0.0009 ms) | the file is read and compiled on *every* call |
| `myString = myString + s` in a loop (290 ms / 10k) | `arr pushBack s;` then `arr joinString ""` (30 ms) | string concat is O(n²) |
| `BIS_fnc_param` | `param` / `params` | ~14× faster |
| `BIS_fnc_MP` | `remoteExec` / `remoteExecCall` | BIS_fnc_MP is a wrapper over them |
| `BIS_fnc_linearConversion`, `BIS_fnc_selectRandomWeighted`, `BIS_fnc_vectorMultiply`, `BIS_fnc_areEqual` | `linearConversion`, `selectRandomWeighted`, `vectorMultiply`, `isEqualTo` | 6–9× faster engine commands |
| `nearestObjects` over >100 m | `nearEntities` | ~2× faster (but only finds alive entities on foot) |
| array-of-pairs + `findIf` lookup (0.0116 ms) | `HASHMAP` + `get` (0.0018 ms) | script loop vs engine hash |
| `arr set [count arr, x]` / `arr = arr + [x]` | `pushBack` / `append` | no array copy |
| `typeName a == typeName b` (0.0018) | `a isEqualType b` (0.0006) | |
| `toLower` / `toUpper` (0.0016) | `toLowerANSI` / `toUpperANSI` (0.0006) | ANSI-only strings |

**Small but free**

| Slower | Faster |
|---|---|
| `if (c) then {a} else {b}` (0.0017) | `[b, a] select c` (0.0011) — only for plain values |
| `count arr == 0` (0.0043) | `arr isEqualTo []` (0.0040) |
| `arr find x > -1` (0.0016) | `x in arr` (0.0012) |
| `for [{…},{…},{…}] do` (0.030) | `for "_i" from 0 to n do` (0.015) |
| `isNil { v }` (0.0012) | `isNil "v"` (0.0007) |
| `format ["%1", n]` (0.0022) | `str n` (0.0016) |
| `arr param [0]` (0.0011) | `arr select 0` (0.0008) — when the index is known-valid |
| `configFile / "X"` | `configFile >> "X"` |
| `vehicle player == player` | `isNull objectParent player` |
| repeated `SomeGlobal select 0` in a loop | copy to a local before the loop (0.13 → 0.08 ms) |
| `private _a = 1;` inside a hot loop | declare once outside, assign inside |

**Loop choice**

- `findIf` short-circuits — use it for "does any element match".
- `count {…}` is marginally faster than `forEach` but its block must return Boolean/Nothing and it
  gives no `_forEachIndex`; adding a trailing `true` to satisfy it makes it slower than `forEach`.
- `for "_i" from 0 to n do` beats `forEach` when you do not need `_x`.
- `select {…}` (filter) beats a `forEach` + `pushBack` (1.55 ms vs 2.57 ms on the wiki's sample).
- `createSimpleObject` is ~35× faster than `createVehicle … "NONE"` for decorative objects.
  `createVehicle … "CAN_COLLIDE"` is far cheaper than `"NONE"` (2.7 ms vs 78 ms) because `"NONE"`
  searches for free space.

**Lazy evaluation** (`a && {b}`) changes both cost and semantics: it can be faster or slower
depending on how often the first condition short-circuits, but its real value is correctness — the
right-hand side is only evaluated when the left-hand side held. Note the bracket placement changes
precedence: `a && {b} || {c}` and `a && {b || {c}}` are different expressions.

## Measuring, not guessing

```sqf
private _t = diag_tickTime;
… code …
diag_log format ["took %1 ms", (diag_tickTime - _t) * 1000];

[{ … }, 10000] call BIS_fnc_codePerformance;   // A/B two implementations
diag_fps, diag_frameNo, diag_activeSQFScripts, diag_activeMissionFSMs
```

Benchmark before and after any "optimisation" that costs readability. If it is not measurably
faster in a real mission, keep the readable version.
