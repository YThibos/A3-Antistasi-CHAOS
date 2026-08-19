# Antistasi CHAOS — Changelog

Newest entries at the top. One line per change when possible.

---

## 2026-08-19

- Construction Yard moved from garage purchase to the Team Leader build catalogue (5000€, `"constructionyard"` ability); button disabled when outside HQ radius or a yard already exists; `fn_buildingComplete` sets `A3A_isConstructionYard` so HQ relocation still works.
- Fix: `fn_relocateHQObjects` and `fn_teamLeaderRTSPlacerDialog` used `Land_Shed_Big_F` to find the Construction Yard — the yard never relocated with HQ and the basetier build gate was always locked. Changed to `a3a_constructionYard` in both; also replaced the inline radius formula in the dialog with `call A3A_fnc_hqBuildRadius`.
- Build boxes: added "Huge construction kit" (`Land_WoodenCrate_01_stack_x3_F`, 2500€) and "Mega construction kit" (`Land_WoodenCrate_01_stack_x5_F`, 5000€).
- AGENTS.md + antistasi-codebase skill: replaced WORK.md workflow references with `docs/CHANGELOG.md`; clarified WORK.md is project-owner-only.
- Reduced utility item purchase cooldown from 15 s to 5 s (`fn_buyItem`).

---

## 2026-08-19 — BAR persistence (commit e4346be)

- BAR: implemented `Persistency_fnc_saveObject` / `Persistency_fnc_removeObject` hooks so BAR calls them on place/demolish; objects now persist across save/load.
- BAR: rewrote `fn_barSave` / `fn_barLoad` using the real BAR variable names (`BuildAndRessources_ressources`, `BuildAndRessources_depotStocks`).
- BAR: rewrote `fn_barResupply` to call `BuildAndRessources_fnc_transferDepotToCrate` instead of guessed variable names.
- AGENTS.md: documented the real BAR API (variable names, persistency hook signatures, transfer function).

---

## 2026-08-18 — BAR + Construction Yard + SQF checker (commit bae2af54)

- Construction Yard (`a3a_constructionYard`, 5000€, commander-only, one per campaign): gates the basetier military build catalogue; relocates with HQ.
- `fn_hqBuildRadius`: single source of truth for HQ build radius (75 m at WT1, +15 m per tier).
- `fn_buyItem`: moved one-per-campaign duplicate check before garage placer to avoid ghost-object false positive (Arma 3 1.94+, `createVehicleLocal` objects appear in `allMissionObjects`).
- BAR crates (`RessourceCrate_*`, 750€) and depot (`RessourceDepot`, 3000€) purchasable from garage; crates have no move/rotate; depot gets a "resupply crates" ACE action (`fn_barResupply`).
- SQF checker: added Python engine `sqfcheck.py` (whole-repo scan ~6 s vs. minutes on PowerShell); BOM detection as E008; dual-engine self-test (`Test-Checker.ps1`); `bad_bom.sqf` fixture.
- Stripped UTF-8 BOM from `fn_initServer.sqf`, `core/Stringtable.xml`, `gui/Stringtable.xml`.

---

## 2026-08-18 — Agent harness and tooling (commit 2ff19e57)

- Added `AGENTS.md` / `CLAUDE.md` working agreement for AI agents.
- Created `.claude/skills/`: `sqf-scripting` (with reference files), `sqf-syntax-check`, `antistasi-codebase`, `arma3-config-and-mission`.
- `Tools/sqfcheck/Check-Sqf.ps1`: structural SQF checker with git-aware `-Changed` / `-Staged` modes, error/warning codes E001–E008 / W001–W004.
- `.claude/settings.json`: PostToolUse hook runs checker on every `.sqf` write.

---

## WP3: ACE Fortify unlock (commit 3c9ce119)

- Activated ACE Fortify Tool unlock on game start; removed stale WP0 TODO scaffolding from `fn_initServer` and `fn_categoryOverrides`.

---

## Rebrand: CHAOS Antistasi (commit 1746acf3)

- New Chaos Group logo assets (`chaos_logo*.paa`); updated `mod.cpp` / `mod_dev.cpp` with CHAOS branding and upstream credit.

---

## WP6: War-tier gate on static weapons (commit 46a74ea1)

- Static weapons (AA/AT/HMG) require War Tier 3 to purchase; Praetorian vehicle unlocks at War Tier 7.

---

## WP5: War-level HQ build radius scaling (commit 88b829c3)

- HQ build zone and builder placement area scale with war tier (applied in `fn_buildingComplete`, `fn_buildingPlacer`, `fn_calcBuildingReveal`, `fn_tierCheck`).

---

## WP4: Construction Yard + basetier military build tier (commit fa4fe437)

- Construction Yard tracks placed object via `A3A_isConstructionYard` variable.
- Basetier catalogue (10 military structures) appended to `A3A_buildableObjects` in `fn_initBuildableObjects`.
- Basetier gate in Team Leader RTS Placer: buttons disabled until Construction Yard is present at HQ.
- `fn_relocateHQObjects`: moves Construction Yard with HQ on relocation.

---

## WP3: BAR Fortify Tool scaffold (commit fe8bcc4d)

- Scaffold to unlock ACE Fortify Tool when BAR mod is present (class name was a TODO).

---

## WP2: BAR resource crates and depot in garage (commit ec76c35a)

- BAR resource crates and depot added to the garage "Other" purchase tab when BAR mod is detected.

---

## WP1: `A3A_hasBAR` mod detection (commit 8523be07)

- Added `A3A_hasBAR` boolean: `true` when the BuildAndRessources mod (`BuildAndRessources.pbo`) is loaded.

