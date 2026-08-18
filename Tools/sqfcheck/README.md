# sqfcheck

A SQF syntax checker for this repository. It always runs with nothing installed at all — pure
PowerShell (5.1+ / pwsh 7+), no Node, no game install — and gets faster when Python is present.

Arma reports SQF syntax errors only at runtime, in `arma3_x64.rpt`, and a broken script usually
just never runs. This catches the structural mistakes before the game does.

## Two engines, one rule set

| Engine | File | Whole-repo scan (1448 files) |
|---|---|---|
| PowerShell | `Check-Sqf.ps1` | minutes |
| Python | `sqfcheck.py` | ~6 s |

`Check-Sqf.ps1` is the entry point either way: when a Python interpreter is on `PATH` (`py`,
`python3` or `python`) it hands the run straight to `sqfcheck.py`. Both engines implement the same
codes, messages and suppression rules, and `Test-Checker.ps1` runs every fixture through both and
fails if they ever disagree — so the fast path can never quietly drift from the portable one.

Pin an engine with `-Engine powershell` or `-Engine python` (the latter fails if no interpreter is
found); `-Engine auto` is the default.

## Usage

```powershell
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed        # everything you changed (normal use)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Staged         # pre-commit
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 path/to/fn.sqf  # one file
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 A3A/addons/gui  # a folder (recursive)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Strict          # + scope safety (W004)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -WarningsAsErrors
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Json            # machine-readable
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Against 6f14150 # vs another ref
```

`-Changed` is a switch and diffs against `HEAD` (plus untracked files); `-Against <ref>` points it
somewhere else. PowerShell has no optional-value parameters, which is why the ref is a separate
flag rather than `-Changed <ref>`.

Exit codes: `0` clean (or warnings only), `1` errors found, `2` bad invocation.
`-Json` always emits valid JSON — `[]` when nothing matched.

`-Changed` is what you want day to day. A full-repo scan is ~6 s on the Python engine, minutes on
the PowerShell one.

The deliberately broken fixtures under `tests/` are skipped by directory and git-based discovery,
so they never turn up in a repo scan or fail CI on a push that touches this folder. Naming one
explicitly still checks it — that is how `Test-Checker.ps1` drives them.

## What it reports

| Code | Level | Meaning |
|---|---|---|
| E001 | error | closing bracket does not match the open one |
| E002 | error | bracket never closed |
| E003 | error | closing bracket with nothing open |
| E004 | error | unterminated string or block comment, or a character the lexer cannot place |
| E005 | error | `#if`/`#ifdef`/`#ifndef` without `#endif` |
| E006 | error | `;` before `else` |
| E007 | error | `;` inside an array literal |
| E008 | error | file starts with a UTF-8 BOM — Arma's preprocessor may not see a leading `#include` |
| W001 | warn | probable missing `;` after a `}` |
| W002 | warn | `,` used at code-block scope inside `{ }` |
| W003 | warn | single `=` inside an `if`/`while`/`waitUntil` condition |
| W004 | warn | local assigned without `private` (`-Strict` only) |

Once a file has a bracket-level error the scope-dependent findings in it are suppressed, because
they would all be cascade noise. Fix the bracket error and re-run.

It understands `//` and `/* */` comments, both quote styles with doubled-quote escaping,
preprocessor directives with line continuations, and treats macro invocations
(`FUNC(x)`, `QGVAR(y)`, `Info_1(…)`) as opaque.

It is **not** an interpreter: it does not know command names, argument types, locality, or whether
`sleep` is legal where you used it. For that, review the code — see `.claude/skills/sqf-scripting`.

## Baseline

`baseline.txt` would hold findings that already exist in inherited upstream code, matched on
file + code + source line (so it survives line-number drift).

**There is no baseline file today, and there should not need to be one**: a full scan of all 1448
`.sqf` files reports 0 errors and 0 warnings. Keep it that way. Regenerate deliberately only:

```powershell
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 A3A -UpdateBaseline
```

Never baseline your own findings to make a run go green.

## Self-test

```powershell
pwsh -NoProfile -File Tools/sqfcheck/Test-Checker.ps1
```

Each fixture in `tests/` declares the codes it must produce on its first line
(`// expect: E001,W001`); `good_*.sqf` fixtures must stay silent. CI runs this before checking the
repository, so a regression in the checker fails loudly instead of hiding real errors.

Every fixture is run through **both** engines and their findings compared code-for-code, so the
two implementations cannot drift apart. When no Python interpreter is present that half is skipped
and the run says so. Two further assertions confirm each engine skips the `tests/` fixtures during
directory discovery.

## Automation

- `Tools/sqfcheck/Invoke-EditHook.ps1` is wired into `.claude/settings.json` as a `PostToolUse`
  hook, so any `.sqf` an agent writes is checked immediately and errors are fed straight back.
- `.github/workflows/sqfcheck.yml` runs the self-test and checks the SQF files touched by a
  pull request.
- Optional local git hook:

```bash
printf '#!/bin/sh\nexec pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Staged\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Related

`Tools/sqfvalidator/` is the vendored Python linter (LordGolias `sqflint`) used by upstream CI. It
does deeper type and scope analysis than sqfcheck — undefined variables, argument types, command
signatures — and now runs on this workstation:

```powershell
py Tools/sqfvalidator/sqflint.py A3A/addons/core/functions/AI/fn_airbomb.sqf
py Tools/sqfvalidator/sqflint.py -d A3A/addons/garage      # recurse a directory
```

It is complementary, not a replacement, and it is **noisy on this codebase**: it does not expand
Antistasi's macros, so every `Info_1(…)`/`Debug_2(…)` line produces a spurious
`can't interpret statement` error. sqfcheck stays the mandatory gate because it is fast,
dependency-free and treats macros as opaque. Reach for `sqflint` when a script fails in a way
structural checking cannot explain, and read its output with that caveat in mind.
