# AGENTS.md — Antistasi CHAOS

Working agreement for any AI agent (Claude Code, Codex, …) working in this repository.
`CLAUDE.md` is a symlink to this file; keep both pointing at the same content.

This is **A3-Antistasi-CHAOS**, a fork of Antistasi Community Edition's `unstable` branch,
shipped as an Arma 3 mod under `A3A/addons/`. The language is **SQF**, plus Arma config
(`config.cpp`, `*.hpp`) and some PowerShell/Python tooling.

## Hard rules

1. **Syntax-check every `.sqf` you touch, every time.**
   `pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed`
   A change with errors is not done. SQF has no compiler: an unchecked mistake becomes a
   silent runtime failure that costs a game session to find.
2. **`private` on every local variable.** SQF is dynamically scoped; an undeclared `_var`
   writes into the caller's scope.
3. **Statements end with `;`** — including `};` after every code block that is not the block's
   return value.
4. **`call`, not `spawn`/`execVM`.** Use the unscheduled environment; use CBA
   (`CBA_fnc_waitAndExecute`, `CBA_fnc_waitUntilAndExecute`, `CBA_fnc_addPerFrameHandler`)
   when you need to wait, never `sleep`/`waitUntil` in event or per-frame code.
5. **Decide locality deliberately.** Server, all clients, or the object's owner? State the answer
   in the function header. Multiplayer-only bugs are almost always locality bugs.
6. **Register new functions in the component's `CfgFunctions.hpp`** — an unregistered
   `fn_*.sqf` simply does not exist at runtime.
7. **Player-visible text goes in `Stringtable.xml`** and is used via `localize`/`LSTRING`.
8. **New persistent state must be added to the save/load functions** under
   `A3A/addons/core/functions/Save/`, or it silently resets on reload.
9. **Log through the macros** (`Info_1`, `Debug_2`, `Error_1`, …), not `diag_log`/`hint`.
   Remove debug leftovers before finishing.
10. **Keep the fork mergeable with upstream `unstable`**: prefer additive changes, keep edits to
    upstream files minimal and local.

## Skills

Project skills live in `.claude/skills/` and are loaded on demand:

| Skill | Load when |
|---|---|
| `sqf-scripting` | writing, editing or reviewing any `.sqf`; reasoning about scheduling, scope, locality or performance |
| `sqf-syntax-check` | before finishing any `.sqf` change; when a script fails silently; when reading a checker finding |
| `antistasi-codebase` | adding/moving a function, touching config, settings, strings, events, or finding where a feature lives |
| `arma3-config-and-mission` | editing `.cpp`/`.hpp` config, adding a class or addon, or reasoning about init order, event handlers and CBA/ACE integration |

`sqf-scripting` has deeper reference files under `references/` (syntax and operators, scoping,
execution model, multiplayer, performance, pitfalls, debugging) — read the one you need.

## Repository map

```
A3A/addons/core        main game logic, macros (Includes/), CfgFunctions.hpp, Params.hpp
A3A/addons/events      declared event bus (Events.hpp + fn_triggerEvent/addEventListener)
A3A/addons/garage gear gui logistics maps tasks patcom jeroen_arsenal config_fixes
Tools/sqfcheck         dependency-free SQF syntax checker (PowerShell) + tests + baseline
Tools/sqfvalidator     vendored Python sqflint (deeper analysis; optional, needs Python)
Tools/Builder          mod build scripts;  build_dev.ps1 / build_stable.ps1 at the root
How to build.md        build setup
WORK.md                this fork's open bugs and improvement notes
.github/workflows      CI: dev build publish, stringtable sync
```

## Workflow

1. Read `WORK.md` and the relevant skill before touching an area.
2. Locate the owning component; extend it rather than piling into `core`.
3. Write the change with a proper function header (arguments, return value, scope, environment).
4. Run the syntax checker on the changed files.
5. Say plainly what was **not** verified — in-game behaviour cannot be tested from the CLI. Never
   claim a feature works when only the syntax was checked.
6. Update `WORK.md` when you fix or discover something listed there.

## Testing reality

There is no automated test harness for gameplay. Verification is:

- syntax check (automated, mandatory),
- reading the code path for locality/scheduling correctness,
- a build (`build_dev.ps1`) if config was touched,
- an in-game session on a **dedicated local server with a separate client** — the only way to
  catch locality, JIP and persistence bugs. Hosted-host testing hides them.

## Notes for future work

Append durable, non-obvious findings about Arma 3 scripting or this codebase here (or into the
matching skill, which is usually the better home). Keep it factual and dated when it refers to a
specific version.

- 2026-08-18: Python is not installed on the captain's workstation, so `Tools/sqfcheck`
  (PowerShell, zero dependencies) is the checker of record; `Tools/sqfvalidator` (Python) remains
  for CI and deeper analysis.
