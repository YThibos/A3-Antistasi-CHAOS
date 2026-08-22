# Antistasi CHAOS — Changelog

Newest entries at the top. One line per change when possible.

---

## 2026-08-22

- **The "Territory reach into empty ground" default is 2.0.** 2.0 x the influence range covers roughly the p90 of Altis objective spacing at the 800 m default, and holds the border contour visibly crisper than 2.5 does; the last few worst-case gaps are left as no-man's-land on purpose. The slider's 0-3.0 range, its half-step quantisation, the faint-cone weight and the cost budgets are all unchanged.
- **Territory now reaches into empty ground: new "Territory reach into empty ground" setting.** One number was doing two jobs - the Influence range decided both how hard a position pushes *and* how far its territory had to stretch to look contiguous, so closing the wide gaps in Altis' northwest meant cranking the range up until a roadblock owned a 1.4 km bubble in the dense half of the map. Every zone now lays a second, much longer, very faint cone on top of its own: `contribution = max(0, 1 - d/R) + W * max(0, 1 - d/(M*R))`, where `M` is the new setting (`A3A_CHAOS_influenceReach`, 0-3 in half steps, default 2.0) and `W` is a fixed weight (`A3A_influenceTailWeight`, default 0.05, sane range 0-0.5, a documented `missionNamespace` override like `A3A_influenceCap` rather than a setting). `R` is still exactly what `A3A_fnc_zoneInfluenceRadii` returns, so the long cone is a multiple of the one radius table and never a second one, and it applies to every side identically. In genuinely empty ground the faint cones are the only thing present, so two distant holdings meet on a line between them and the gap closes; ground further than `M*R` from every zone is still reached by nothing and stays no-man's-land. A single neighbour's faint cone can pull a fading rim inward by at most `W*R` - 40 m at the 800 m default, well under one grid cell - so borders that two real presences contest do not move perceptibly. `M = 0` restores the old model exactly, hard gaps and all, and costs one comparison per rasterised node. The setting and the weight are both in the overlay's staleness signature, and `fn_debugMapOverlay` reports them.
- **The long reach is paid for in outline resolution, not in time.** Its support is `M*R`, so it widens the sampled bounds and multiplies each zone's rasterised area by `M^2`; the node and rasterisation budgets are deliberately unchanged, so the adaptive grid answers by coarsening. Simulating the grid loop over the Altis census at the 800 m range and reach 2.5: the cell goes 151 m -> 288 m at campaign start (~144 zones) and 151 m -> 373 m on a fully built-out late-game map (~295 zones), with the node count *falling* in both cases (28k -> 11k and 28k -> 7k), so the border gets blockier while the work per recompute stays inside the same budget. Reach 2.0 costs about one growth step less. The grid margin is now derived from the reach rather than being a flat two cells, because the 1.5-cell radius floor reaches `1.5 * M` cells once the long cone is on; with the long cone off it is still exactly two cells.
- **Fix: every side's influence border was drawn in the same neutral grey.** The overlay read each side's colour with `getArray (configFile >> "CfgMarkerColors" >> ... >> "color")` and only accepted the channels when they were numbers. They never are: A3's own side entries (`ColorWEST` / `ColorEAST` / `ColorGUER` and the `colorBLUFOR` / `colorOPFOR` / `colorGUER` aliases the mission uses) store each channel as a *string* holding an expression such as `"(profilenamespace getvariable ['Map_BLUFOR_R',0])"`, so the player's own map colour preferences apply. Every read therefore failed and all three sides took the single grey fallback. `fn_computeInfluenceZones` now takes a numeric channel as-is, evaluates a string channel and accepts it only when it resolves to a finite number, clamps every channel to 0-1, and falls back **per side** (Guerilla green, Occupants blue, Invaders red) rather than to one shared grey - a resolved colour whose three channels are all equal counts as a failed read for the same reason. A fallback logs the class name and the colour used at debug level.
- **The influence overlay now guarantees the three sides are drawn in different colours.** The per-side grey rule above can only judge one side at a time, and there is a way to fail with three individually valid reads: every side class resolves its channels off `profileNamespace`, and the config defaults behind those reads are `[0,1,1]` for BLUFOR, OPFOR and Independent alike, so a profile that never set its map colours resolves all three sides to the same cyan. After the per-side pass, every pair of resolved colours is compared with a 0.05-per-channel tolerance - two barely distinguishable borders are as useless as two identical ones - and on any collision *all* sides drop back to the per-side fallbacks (Guerilla green, Occupants blue, Invaders red). The colliding pair and the colour they shared are logged at debug level.

## 2026-08-21

- **The influence overlap ceiling is tunable at runtime for testing.** `A3A_influenceCap` (default 1, sane range 0.05-100) and `A3A_influenceCapTail` (default 0.05, sane range 0-1) can be set from the debug console mid-session; both are folded into the overlay's staleness signature, so a change is picked up within 2 seconds of a map being drawn instead of waiting for territory to shift. Deliberately not CBA settings - the numbers are internal model constants and mean nothing in a settings UI. Values that are not numbers, out of range, or NaN fall back to the default, which is what keeps a cap of zero or less from dividing by zero in the saturation. `fn_debugMapOverlay` reports both.
- **Rebel training now widens the Guerilla border only.** The `skillFIA` training factor (0.8x at 1/20 to 1.2x at 20/20) was multiplied into every zone's influence radius regardless of owner, so buying rebel training also pushed the Occupants' and Invaders' borders outwards. It is applied to `teamPlayer` zones now; the other two sides get no training factor. `A3A_fnc_zoneInfluenceRadii` lost its scale argument and is a pure per-type table again.
- **The rebel HQ now projects influence like an outpost (1.25x the Influence range).** Its influence radius used to be `A3A_fnc_hqBuildRadius` literally (75 m at war tier 1), which is well under one grid cell on an Altis-sized map, so the overlay's 1.5-cell radius floor was setting the HQ's reach and an early-campaign HQ produced no contour segments at all. The HQ *build* radius and the `"Synd_HQ"` claim ring are unchanged and still grow with the war tier; only the influence field's radius moved.
- **Influence model reworked: one range, per-zone-type multipliers, all three sides.** Friendly zones used to project at the global link distance (2 km) while enemy zones pushed back with only their marker footprint (~200 m outpost, 30 m roadblock), so a 30 m roadblock claimed a 2 km bubble and enemy borders showed up only where they happened to fall inside the inflated friendly field. Influence radius is now a property of the zone TYPE, applied identically to every side: roadblock 0.75x, watchpost / camp / resource / factory / seaport 1x, outpost 1.25x, town 0.75x-1.5x scaled by its marker size, airfield 1.75x, rebel HQ = `A3A_fnc_hqBuildRadius`. The whole table lives in new `A3A_fnc_zoneInfluenceRadii`. Every radius is scaled again by rebel AI training (`skillFIA`), 0.8x at 1/20 to 1.2x at 20/20.
- The `A3A_CHAOS_influenceLinkDist` slider (1000-5000 m, default 2000) is replaced by **Influence range** (100-1400 m in steps of 100, default 800), matching the upstream spawn-distance slider idiom. It is the reference radius the type multipliers scale off, not an absolute link distance.
- Overlapping zones now **add with a ceiling**: a side's influence at a point is the sum of `1 - distance/radius` over its zones, saturated at 1 (plus a 5% tail that keeps the ordering strict). However many roadblocks are stacked on one spot they can never out-push a single large zone.
- **Three sides are drawn, not two.** Guerilla, Occupants and Invaders each get their own field and their own contour, extracted where that side's influence beats every other side's. Sides are collected from the zones that actually exist, so a configuration running Occupants only never touches an Invaders code path. All three share one grid and one marching-squares pass; measured against an Altis-sized census the three-side pass costs 0.86x-1.08x the old two-side one at the same grid resolution.
- **Border thickness setting** (1-8 px, default 4). `drawLine` has no width parameter, so thickness is N parallel copies offset perpendicular by whole screen pixels, using a normal precomputed per segment; the band keeps a constant width at every zoom. A line budget trims thickness (never segments) on a huge late-game map.
- **Colours are no longer chosen by hand.** The colour dropdown is gone; each side is drawn in its own faction colour read from `CfgMarkerColors` via `colorTeamPlayer` / `colorOccupants` / `colorInvaders`, so the overlay matches the map's own markers on any world and any config, and the previous over-bright greens are replaced by Independent green, BLUFOR blue and OPFOR red at a legible alpha.
- **New fill toggle and opacity slider** (default off, 0.25). `drawPolygon` cannot fill - the Biki says so explicitly and points at `drawTriangle` - so the compute emits a triangle soup per side, built from the same grid cells the contour comes from: whole runs of interior cells merged into rectangles, and each boundary cell cut into the polygon that belongs to that side. Concavity is a non-issue because every triangle is convex, and enclosed pockets need no handling: a pocket in your territory belongs to someone else and that side's own pass paints it.
- **The HQ area now grows with the base.** `"Synd_HQ"` was a fixed 75 m circle, so the area in which a placed static or vehicle counts as HQ property never changed, while the HQ *build* radius grew from 75 m to 210 m with the war tier. New `A3A_fnc_updateHQMarkerRadius` resizes the HQ area marker to `A3A_fnc_hqBuildRadius` at server init and whenever `fn_tierCheck` changes the war tier. Because every "is this inside the HQ" rule in the codebase is an `inArea "Synd_HQ"` test (`fn_getMarkerForPos`, `fn_rebelVehPlacedWorker`, `fn_buildHQ`), they all follow the growing radius at once, and the map overlay's HQ ring follows it for free.
- **Fix**: saving the game raised "Variable 'a3a_influencemapctrl' does not support serialization and should not be stored in the mission namespace". The cached vanilla-map control and its attach-retry flag are stored in `uiNamespace` now, which Arma never serialises; the attach guard is reset at client init so a mission change cannot inherit a stale one. Everything else the overlay caches is plain numbers and arrays.
- **Zone of influence overlay reworked into an actual border.** The overlay no longer draws one translucent triangle per triple of nearby friendly zones. `fn_computeInfluenceZones` now samples a friendly-minus-enemy influence field on an adaptive grid and extracts its zero contour with marching squares, so the map shows a drawn outline of friendly territory: several separate outlines for disjoint territory, inner outlines around enemy holdings enclosed by friendly ground, and no special-casing for 0/1/2 zones, collinear or duplicated positions, or separate landmasses. The grid cell size grows until the work fits a fixed budget, which replaces the old 80-zone cut-off that silently switched the feature off exactly when the player owned the most ground.
- Zone claim areas are now drawn in the marker's own shape (`drawRectangle` for RECTANGLE markers, `drawEllipse` for ELLIPSE), so what is drawn matches the `inArea` test `fn_getMarkerForPos` actually uses. HQ uses its marker size rather than the build radius, for the same reason. New per-client toggle for this layer.
- Enemy roadblocks and camps (`controlsX`) now push the border back, instead of only enemy `markersX` centres being tested for containment.
- Overlay refresh is event-driven: `fn_initMapOverlay` listens to the existing `markerChange`, `RebelControlCreated` and `HQPlaced` events on the server and publishes a revision counter. Clients recheck at most twice a second and only recompute when a cheap signature of the zone data changed, which also covers the cases with no event of their own (watchpost demolition, save/load, JIP). The 10-minute resource-tick broadcast in `fn_resourcecheck` is gone, restoring that file to upstream.
- Fixes: `fn_debugMapOverlay` was never registered in `CfgFunctions` and did not exist at runtime; the per-frame handler's args were double-wrapped so the map-open branch that attaches the Draw EH could be skipped; the Draw EH bailed on `!visibleMap`, which is only ever true for the vanilla map and therefore disabled all three Y-menu maps; the Y-menu maps could also never have data because only the vanilla-map path computed any. The permanent every-frame handler is replaced by a `"Map"` mission event handler plus a self-removing attach retry, and the attach guard is the stored control, so a destroyed and recreated map display re-attaches.
- CBA settings: renamed `A3A_CHAOS_influenceTriangleDist` to `A3A_CHAOS_influenceLinkDist`, added `A3A_CHAOS_influenceShowClaimAreas`, and moved all Map Overlay setting titles and tooltips into `Stringtable.xml`.
- `fn_garrisonVehicleRadius`: documentation said the watchpost claim area is a 30 m square; `inAreaArrayIndexes` defaults to an ellipse, so it is a 30 m circle. The marker argument is now optional, and `fn_getMarkerForPos` asks for the constant directly instead of reading the radius of watchpost #0 and applying it to every post.
- Housekeeping: reverted trailing-whitespace churn in `fn_hqDialog`, `fn_mainDialog`, `fn_resourcecheck` and `fn_initSpawnPlaceStats`; untracked the generated `docs/current_modlist.html`.

---

## 2026-08-20

- **Garrison vehicle claim radius**: extracted the hardcoded 30 m watchpost claim radius into new `A3A_fnc_garrisonVehicleRadius` (documents all marker-type rules in one place); `fn_getMarkerForPos` now calls it instead of using a magic number.
- **Dev tooling**: added `setup_test_env.ps1` (gitignored) — generates `server.cfg`, `start_server.ps1`, `start_client.ps1`, `sync_save.ps1` for a local dedicated-server test loop; updated `.gitignore` to cover all generated files; rewrote `WORK.md` as a concrete reference with resolved paths and full mod list.

- **Map overlay, second attempt**: moved the vanilla-map Draw EH attach into a CBA per-frame handler because `findDisplay 12 displayCtrl 51` is `controlNull` while the map is closed; attached the same Draw EH to the Y-menu commander / fast-travel / garrison maps; added a colour dropdown setting and `fn_debugMapOverlay`. Superseded by the 2026-08-21 rework.

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

