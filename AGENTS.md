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
   make. Newest entries go at the top. Do not edit `tmp/WORK.md` — that file belongs to the project
   owner and is not committed to the repo.

## Testing reality

There is no automated test harness for gameplay. Verification is:

- syntax check (automated, mandatory),
- reading the code path for locality/scheduling correctness,
- a build (`build_dev.ps1`) if config was touched,
- an in-game session on a **dedicated local server with a separate client** — the only way to
  catch locality, JIP and persistence bugs. Hosted-host testing hides them.

## Reporting back to the project owner

Every report in this repository uses the same structure, in this order:

1. **Done** - everything that was changed, as a flat enumerated list.
2. **Findings** - what was discovered for each of those items, keyed to the same numbers.
3. **Needs your input** - at the bottom, everything awaiting a decision or a test result.

Number every item so it can be replied to individually: `1a`, `1b`, `2a`, `2b`, `3a`.
The point is that the owner can answer a specific point without re-reading the whole
report, so keep the identifiers stable within a report and never bury a question in
prose above the input section.

## Documents and briefings

`docs/` briefings and any shared write-up follow the design established by the supply
layer briefing (published 2026-09-02): a technical-spec treatment, olive-biased
neutrals rather than generic grey, the mod's own side colours (Guerilla green,
Occupant blue, Invader red) as semantic accents, Saira Condensed headings with
Source Sans 3 prose and JetBrains Mono for formulae, and layered section numbering
only where the content genuinely stacks. Load the `artifact-design` skill and treat
that page as the house baseline rather than starting a new visual identity.

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
- 2026-08-20: **Vanilla M-map Draw EH** — `findDisplay 12 displayCtrl 51` is the vanilla map
  control. This is general Arma 3 knowledge, not something this codebase corroborates: the only
  `idc = 51` in the repo is `A3A/addons/gui/dialogues/controls.hpp`, which is A3A's *own* dialog
  map class and says nothing about display 12. The control is created lazily and returns
  `controlNull` while the map is closed, so a Draw EH cannot be attached at init time. Use the
  `"Map"` mission event handler to learn when the map opens, and retry the attach from a
  short-lived CBA per-frame handler that removes itself once the control resolves — that avoids
  leaving a permanent every-frame handler on every client. Store the *control* rather than the
  event-handler id as the attach guard, so a destroyed and recreated display re-attaches itself.
- 2026-08-21: **`visibleMap` is only true for the vanilla map.** A Draw EH shared between the
  vanilla map and the Y-menu dialog map controls must not guard on `visibleMap`, or it silently
  draws nothing in every dialog. No other Draw EH in this repo checks it. A Draw EH only fires
  while its control renders, so the guard buys nothing anyway.
- 2026-08-21: **CBA per-frame handler args are passed whole.** `[{...}, 0, _args] call
  CBA_fnc_addPerFrameHandler` invokes the callback with `_this = [_args, _handle]`, so
  `params ["_args"]` yields exactly what was passed. Passing `[[false]]` and then reading
  `_args # 0` yields the inner array, not the boolean — a type error that only shows up on the
  frames where the value is actually read.
- 2026-08-31: **The influence field has one owner now.** `A3A_fnc_influenceContext` holds zone
  collection, per-type radii, the training factor and every model constant; `fn_computeInfluenceZones`
  (client raster) and `A3A_fnc_computeSupplyGraph` (server corridor test) are both built on it, so
  the drawn border and supply connectivity cannot drift. `A3A_fnc_influenceAt` is the gather form of
  the same maths the raster scatters - the four lines of cone/saturation arithmetic are duplicated
  on purpose (a function call per grid node would cost the overlay far more than the duplication
  costs us), so a change to one needs the same change in sections 5-6 of the raster.
  The raster floors radii at 1.5 grid cells; that floor belongs to the grid, not the field, and is
  deliberately absent from point queries.
- 2026-08-31: **CBA setting scope is load-bearing, not cosmetic.** `A3A_CHAOS_influenceRange` and
  `A3A_CHAOS_influenceReach` were `isGlobal 0` (per-client) while the overlay was decoration, which
  merely meant two players saw slightly different borders. The moment the server derived supply
  connectivity from the same numbers that became a correctness bug, and they are now `isGlobal 2`
  (this repo's convention for server-forced). Rule of thumb: geometry settings global, presentation
  settings per-client. Note that promoting a setting drops any per-client value players had set.
- 2026-08-31: **`fn_chooseAttack` targets markers, not objects.** A destructible object placed at a
  marker - a BAR depot, say - is therefore only ever attacked incidentally, as part of an attack on
  its marker. Any design that relies on "the enemy will destroy this thing" needs a mission type
  added to the attack director; it does not fall out of the existing AI.
- 2026-08-31: **The economy is normalised per map and does not tolerate naive multipliers.**
  `fn_initZones` sets `A3A_rebelCashResMult = 1500 / count resourcesX` and
  `A3A_rebelCashFactMult = 1.4 / count factories`, so every map's resources are collectively worth
  1500/tick and its factories +140%, whatever the count. Resources are the ADDITIVE cash term and
  factories the MULTIPLIER, so tiering both compounds. Also: those multipliers are computed once at
  init and `fn_tierCheck` derives `_totalPoints` from the same counts, so a marker added mid-campaign
  is worth a full undiluted share AND can retroactively move the war tier.
- 2026-08-31: **Enemy factions do have resource pools** - `A3A_resourcesAttackOcc/Inv` and
  `A3A_resourcesDefenceOcc/Inv` in `fn_aggressionUpdateLoop`, fed by `A3A_balanceResourceRate`. The
  loop already carried a territorial modifier (no airport -> x0.6 / x0.2), which is the precedent
  supply connectivity follows. Because defence is capped at `rate * 100`, changing the rate also
  moves the stockpile ceiling.
- 2026-09-02: **A task params function returns `[weight, argumentList]`, and element 1 is the
  WHOLE argument list.** `fn_requestTask` hands `_params # 1` straight to the task function,
  whose own `params` unpacks it. The single-value tasks return
  `[1, [selectRandomWeighted ...]]` because their picked value is one string and the brackets
  ARE the list - copying that shape for a multi-value pick double-nests it, binds the first
  argument to an array and the rest to nil, and throws inside the spawned task. The symptom is
  distinctive: Petros announces the mission every time and never creates one, repeatable
  forever, because the throw happens before `A3A_activeTasks` is touched.
- 2026-09-02: **`NATO_carrier` and `CSAT_carrier` are the enemy off-map support corridors.**
  `fn_initVarServer` only sets their marker TEXT from the faction template; they are not in
  `markersX`, no side owns them in `sidesX`, and they project no influence unless something
  adds them explicitly. They are the natural root for an enemy supply network - an occupying
  army's supply comes from off the map, not from a base.
- 2026-09-02: **Derive state from the world before you store it.** CHAOS site tiers were
  designed as a saved number per marker and shipped as a derivation instead: the tier IS
  which structures stand on the site (`A3A_fnc_siteTiers`). That removed the save/load work
  entirely, made "destroy it and the tier drops" free, and dodged a real trap - a building
  restored from a save does NOT carry its custom `setVariable` data back, so a
  variable-based marker would have wiped every tier on campaign reload. Class plus
  proximity survives anything that can restore the building at all.
- 2026-09-02: **`fn_runTask`'s stage/constructor framework is commented out.** Lines 1-104
  of `A3A/addons/tasks/Core/fn_runTask.sqf` are one big block comment; the live driver is
  the state-machine loop below it (`state` / `checkpoint` / `interval` keys on a task
  hashmap). `isLegacy = 0` in `Tasks.hpp` selects that loop, not the stages. Copy
  `fn_SUP_Supplies.sqf`, not the commented header, when writing a new task.
- 2026-09-02: **`A3A_Logistics_fnc_getCargoConfig` matches CLASS NAME before model.** So a
  new loadable object needs a `class Land_Whatever_F` entry in `Cargo/Vanilla.hpp` and no
  p3d path at all - which is both less brittle and immune to Bohemia moving a model.
- 2026-09-02: **A utility item priced -1 is registered but unpurchasable.**
  `A3A_utilityItemList` filters on `price >= 0` while `A3A_utilityItemHM` keeps everything,
  so -1 is how a mission-spawned object still gets flags, persistence and actions.
  Paired with `fn_lockBuilderBox`, which DELETES a builder box released with no budget
  left, a mission container whose `A3A_itemPrice` equals its one buildable's price
  disposes of itself the moment that building is paid for.
- 2026-08-20: **`Tools/StreetArtist`** is a standalone navGrid-generation mission tool (separate
  Arma 3 mission, not part of the mod). Its `findDisplay 12 displayCtrl 51` usage is inside an
  `EachFrame` EH that already guards `!visibleMap`, making it useless as a general reference for
  map overlay code. Do not cite it to justify display/control access patterns in the mod.
