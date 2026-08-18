# sqfcheck

A dependency-free SQF syntax checker for this repository. Pure PowerShell (5.1+ / pwsh 7+):
no Python, no Node, no game install needed.

Arma reports SQF syntax errors only at runtime, in `arma3_x64.rpt`, and a broken script usually
just never runs. This catches the structural mistakes before the game does.

## Usage

```powershell
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed        # everything you changed (normal use)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Staged         # pre-commit
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 path/to/fn.sqf  # one file
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 A3A/addons/gui  # a folder (recursive)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Strict          # + scope safety (W004)
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -WarningsAsErrors
pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed -Json            # machine-readable
```

Exit codes: `0` clean (or warnings only), `1` errors found, `2` bad invocation.

A full-repo scan takes several minutes (~20 MB of SQF); `-Changed` is what you want day to day.

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
`.sqf` files reports only 2 errors and 0 warnings, all of them genuine (two files end in an
unterminated `/* … ` comment block). Keep it that way. Regenerate deliberately only:

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
does deeper type/scope analysis but needs Python installed; sqfcheck deliberately has no
dependencies so it always runs.
