---
name: sqf-syntax-check
description: How to syntax-check SQF in this repository with Tools/sqfcheck. Load and run before finishing any change that touches a .sqf file, when a script fails silently in game, or when interpreting a checker finding.
---

# Syntax-checking SQF

**Rule: no `.sqf` edit is finished until the checker passes on it.** Arma reports syntax errors
only at runtime, in a log file, often as a script that simply never runs.

## Run it

```powershell
# everything you changed (git-aware; the normal case)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed

# specific files or a folder
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 A3A/addons/core/functions/AI/fn_airbomb.sqf
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 A3A/addons/garage

# staged changes only, before committing
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Staged

# extra scope-safety pass (flags locals assigned without `private`)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Strict
```

Exit code `0` = clean or warnings only, `1` = errors, `2` = bad invocation.
Add `-WarningsAsErrors` to fail on warnings too, `-Json` for machine-readable output.

A whole-repo scan (`… Check-Sqf.ps1 A3A`) takes several minutes — use `-Changed` for normal work.

## What the codes mean

| Code | Meaning | Fix |
|---|---|---|
| E001 | Closing bracket does not match what was opened | Look at the *opening* line named in the message, not only the reported line |
| E002 | Bracket never closed | Usually a `}` or `]` deleted during an edit |
| E003 | Closing bracket with nothing open | One `}` too many |
| E004 | Unterminated string / block comment / stray character | Check quote pairing; SQF escapes quotes by doubling them (`""`) |
| E005 | `#ifdef`/`#if` without `#endif` | Preprocessor conditionals must balance per file |
| E006 | `;` before `else` | `if (…) then { … } else { … };` is one statement |
| E007 | `;` inside an array literal | Array elements are separated by `,` |
| W001 | Probable missing `;` after a `}` | The classic SQF break; add `};` |
| W002 | `,` at code-block scope | Statements in `{ }` are separated by `;` |
| W003 | Single `=` inside a condition | Use `==` or `isEqualTo` |
| W004 | Local assigned without `private` (`-Strict`) | Add `private`; SQF is dynamically scoped, so it otherwise writes into the caller's scope |

Once a file has a bracket-level error, scope-dependent findings in it are suppressed as noise —
fix the bracket error and re-run.

## Legacy noise and the baseline

`Tools/sqfcheck/baseline.txt` can hold findings that already existed in inherited upstream code,
matched on file + code + source line so it does not drift when line numbers move.

There is **no baseline file today** — a full scan of all 1448 `.sqf` files reports 2 errors and no
warnings, and both are real (a file ending inside an unterminated `/* … ` comment). A finding in a
run is therefore almost certainly yours.

- Fix your own findings. Never add them to the baseline to make a run go green.
- `-UpdateBaseline` (whole-repo scan) is for a deliberate, reviewed re-baselining only.
- `-Baseline <path>` points at a different file; a non-existent path disables baselining.

## Limits — what it cannot catch

It is a structural checker, not an interpreter. It does **not** know about:
undefined functions or commands, wrong argument types, locality mistakes, `sleep` in an
unscheduled context, or a macro whose expansion is itself broken. Those need review and testing —
see the `sqf-scripting` skill.

Macro invocations (`FUNC(x)`, `QGVAR(y)`, `Info_1(…)`) are treated as opaque, so a missing `;`
directly after a macro call is not flagged.

## Automatic checking

`.claude/settings.json` registers a `PostToolUse` hook that runs the checker on every `.sqf` file
written or edited in this repo. If it reports an error, fix it in the same turn — do not move on.

The vendored Python linter under `Tools/sqfvalidator` (LordGolias `sqflint`) does deeper type and
scope analysis and is still useful when Python is available; it is not required, and
`Tools/sqfcheck` intentionally has no dependencies.
