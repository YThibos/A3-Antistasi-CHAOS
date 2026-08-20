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
Tools/sqfcheck         SQF syntax checker: PowerShell + Python engines, same rules, + tests
Tools/sqfvalidator     vendored Python sqflint (deeper analysis; run with `py`, noisy on macros)
Tools/pboextract       reusable PBO extractor (CLI + library); see its README.md
Tools/Builder          mod build scripts;  build_dev.ps1 / build_stable.ps1 at the root
How to build.md        build setup
docs/CHANGELOG.md      fork changelog — append a line here for every change you make
WORK.md                project owner's private notes; not tracked by agents, not committed
.github/workflows      CI: dev build publish, stringtable sync
```

## Workflow

1. Read the relevant skill before touching an area.
2. Locate the owning component; extend it rather than piling into `core`.
3. Write the change with a proper function header (arguments, return value, scope, environment).
4. Run the syntax checker on the changed files.
5. Say plainly what was **not** verified — in-game behaviour cannot be tested from the CLI. Never
   claim a feature works when only the syntax was checked.
6. Append a brief entry to `docs/CHANGELOG.md` (single line when possible) for every change you
   make. Newest entries go at the top. Do not edit `WORK.md` — that file belongs to the project
   owner and is not committed to the repo.

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

- 2026-08-18: `Tools/sqfcheck` is the checker of record. It ships two engines with an identical
  rule set — `Check-Sqf.ps1` and the much faster `sqfcheck.py` — and delegates to the Python one
  automatically when an interpreter is on `PATH`, so hard rule 1's command is unchanged either way
  (a whole-repo scan drops from minutes to ~6 s). `Test-Checker.ps1` runs every fixture through
  both engines and fails if they disagree.
- 2026-08-18: Python 3.14 **is** installed on the captain's workstation, but only as the `py`
  launcher — `python` and `python3` are not on `PATH` in Git Bash. Anything invoking Python
  directly must use `py`, or probe all three names the way the checker does. (Supersedes an
  earlier note in this file that said Python was unavailable.)
- 2026-08-18: `Tools/sqfvalidator` (vendored LordGolias `sqflint`) therefore runs too, via
  `py Tools/sqfvalidator/sqflint.py <file>` or `-d <dir>`. It does deeper type and scope analysis,
  but it does not expand this codebase's macros, so every `Info_1(…)`/`Debug_2(…)` call yields a
  spurious "can't interpret statement" error. A second opinion, never a gate.
- 2026-08-19: `Tools/pboextract/pboextract.py` is the canonical PBO extractor. It handles plain
  PBOs and the sreV properties format, works as a CLI (`py Tools/pboextract/pboextract.py <file>
  [dest] [--exts sqf,hpp] [--list] [-v]`) and as an importable library (`PboReader`). Replaces
  the one-off scripts in `build/extract_bar*.py`. Always import/call it rather than re-implementing
  PBO parsing inline. See `Tools/pboextract/README.md` and the `antistasi-codebase` skill.
- 2026-08-19: **BAR (BuildAndRessources) real API** — verified by extracting
  `BuildAndRessources.pbo` (Python PBO parser in `build/read_pbo.py`).
  Key facts for integration code:
  - Crate resource array variable: `BuildAndRessources_ressources` — 4-element array
    `[Concrete, Wood, Sand, Metal]`, set with `setVariable [..., true]`.
  - Depot stock variable: `BuildAndRessources_depotStocks` — same 4-element format;
    -1 = infinite stock.
  - Resource type order comes from global `BuildAndRessources_names = ["Concrete","Wood","Sand","Metal"]`.
  - Crate classes: `RessourceCrate_Concrete/Wood/Sand/Metal`. Depot: `RessourceDepot`.
  - Depot transfer radius: `_depot getVariable ["BuildAndRessources_depotTransferRadius", 50]`.
  - BAR calls `Persistency_fnc_saveObject` (with `[[obj]]` via `remoteExecCall` to server 2)
    and `Persistency_fnc_removeObject` (with `[obj]`) if those functions exist. Register them
    in `CfgFunctions` so they are auto-whitelisted for `remoteExec`. Note: `deleteVehicle` is
    called **before** `remoteExecCall ["Persistency_fnc_removeObject",2]`, so the object
    reference arrives as `objNull` on the server — do not rely on it for lookup.
  - `BuildAndRessources_fnc_transferDepotToCrate [_depot, _crate]` — the canonical server-side
    transfer call; skips caller-distance check when called directly (not via remoteExec).
- 2026-08-20: **Vanilla M-map Draw EH** — `findDisplay 12 displayCtrl 51` is the correct map
  control (confirmed by Arma 3 community + codebase IDC 51 usage), BUT the control is lazily
  created and returns `controlNull` when the vanilla map is closed. Always attach a Draw EH from
  within code that runs while `visibleMap == true`, not at init time. The CBA 0-delay PFH is the
  right place: check `!_wasOpen && _isOpen` to catch the first open frame.
- 2026-08-20: **`Tools/StreetArtist`** is a standalone navGrid-generation mission tool (separate
  Arma 3 mission, not part of the mod). Its `findDisplay 12 displayCtrl 51` usage is inside an
  `EachFrame` EH that already guards `!visibleMap`, making it useless as a general reference for
  map overlay code. Do not cite it to justify display/control access patterns in the mod.
