# Antistasi CHAOS — Changelog

Newest entries at the top. One line per change when possible.

---

## 2026-08-20

- **Garrison vehicle claim radius**: extracted the hardcoded 30 m watchpost claim radius into new `A3A_fnc_garrisonVehicleRadius` (documents all marker-type rules in one place); `fn_getMarkerForPos` now calls it instead of using a magic number.
- **Dev tooling**: added `setup_test_env.ps1` (gitignored) — generates `server.cfg`, `start_server.ps1`, `start_client.ps1`, `sync_save.ps1` for a local dedicated-server test loop; updated `.gitignore` to cover all generated files; rewrote `WORK.md` as a concrete reference with resolved paths and full mod list.

## 2026-08-20

- **Map overlay fix v3**: `findDisplay 12 displayCtrl 51` is lazily created — returns `controlNull` when the vanilla map is closed. Fixed by moving `ctrlAddEventHandler` into the CBA 0-delay PFH; it now runs on the first frame `visibleMap` becomes true. Added overlay to Y-menu commander / fast-travel / garrison maps (proven working path, same pattern as existing Draw EHs). Added colour dropdown CBA setting (7 presets). Added `fn_debugMapOverlay` diagnostic function. StreetArtist is a standalone navGrid tool not part of the mod — removed as a reference.

- Military (basetier) build catalogue moved out of the general build boxes into a new box type: **Military construction kit** (`Land_Pallet_MilBoxes_F`, 3000€, garage "Other" tab). Only that box lists the military-tier structures; the ordinary kits now show the civilian catalogue only.
- The kit itself is the gate: it can only be bought once a Construction Yard is built (new `"yardonly"` item flag, checked in `fn_buyItem` and greyed out with a tooltip in the garage tab). The per-item "yard + inside HQ radius" gate in the placer dialog is gone, so military structures can now be built wherever the kit is hauled to, not only at HQ.
- New `A3A_fnc_hasConstructionYard` (core/Base): single source of truth for the yard test, replacing the two copies in `fn_teamLeaderRTSPlacerDialog`.
- New item flag `"basetier"` on a build box marks it as carrying the military catalogue; the placer dialog filters `A3A_buildableObjects` by the flags of the box in use.

---

## 2026-08-19

- Map influence overlay: added two CBA Addon Options under "Antistasi CHAOS > Map Overlay" — "Show influence zone overlay" toggle (per-client, default on) and "Triangle zone max distance" slider (1 000–5 000 m, default 2 000 m, snapped to nearest 100 m, live-update via onChange). Toggle gates the draw EH per-frame; distance slider drives both the BFS graph and the triangle pair checks in `fn_computeInfluenceZones`.
- Map influence overlay: client-side transparent green ellipses on the vanilla M-map show the static-attribution radius of every friendly capturable zone (cities, outposts, resources, factories, seaports, airports, roadblocks, watchposts, HQ build radius); filled green triangles mark compact clusters of friendly zones reachable from HQ whose interiors contain no enemy sites. Overlay data is recomputed on each map-open and refreshed automatically when the server's 10-minute resource tick broadcasts `A3A_influenceZonesDirty`. New functions: `A3A_fnc_computeInfluenceZones` (core/Base), `A3A_GUI_fnc_mapDrawInfluenceEH` (gui/GUI), `A3A_fnc_initMapOverlay` (core/init).

- Fix: vanilla `hint`/`hintSilent` boxes from other mods were wiped every ~15 frames — `fn_customHintRender` was calling `hintSilent ""` on every render tick even when the A3A queue had been empty for a long time. Added `A3A_customHint_WasShowing` flag: the hint box is now cleared only on the single frame the queue drains to empty, leaving external hints untouched thereafter.
- `Tools/pboextract/pboextract.py`: new reusable PBO extractor (CLI + library); replaces `build/extract_bar*.py`; handles sreV-headers, extension filters, `--list` mode; documented in `antistasi-codebase` skill and `AGENTS.md`.
- Fix: CHAOS CBA Addon Options not appearing — `preInit = 1` runs at mission start, not game startup. Moved registration to `Extended_PreInit_EventHandlers` in `config.cpp` (same mechanism BAR uses for its settings).
- New CBA Addon Option "Antistasi CHAOS > Construction > Build time multiplier" (`A3A_CHAOS_buildTimeMult`, default 1.0, range 0.1–5.0). Applies to Antistasi build-box hold times (`fn_placeBuilderObjects`) and BAR structure placement times (via `BuildAndRessources_fnc_placeObject` wrapper installed on each client). ACE Fortify's own "Time-Cost Coefficient" setting has no effect on either system — Antistasi uses vanilla hold-actions and BAR only checks ACE_Fortify as an item prerequisite.
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

