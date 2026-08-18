# Antistasi CE 3.11.1 — BuildAndRessources integration & tiered base building

**Audience:** a coding agent working in a fork of `official-antistasi-community/A3-Antistasi`.

**Verified against:** commit `6f14150` (18 Apr 2026), which is the 3.11.1 release. All file paths and line numbers below were read from that tree. Line numbers are approximate anchors — locate by surrounding code, not by number alone.

**Server modlist this targets:** ACE, CBA, BuildAndRessources, AAS Core, Vanilla CRAM, CUP Units/Vehicles/Weapons, BWMod, ITC Land Systems, Gruppe Adler Trenches, Advanced Sling Loading, Zeus Enhanced, Enhanced Movement, plus QoL mods. Note: **no CUP Terrains Core** — CUP contributes vehicles/statics/weapons but no structures.

---

## 1. Goal and architecture

Today, BAR's resource crates and Fortify Tool are only reachable via Zeus or scripts, and Antistasi's own build boxes all draw from a single flat per-map catalogue. The end state is four distinct build tiers with clearly separated roles:

| Tier | System | Feel | Scope | Paid with |
|---|---|---|---|---|
| T0 | Gruppe Adler Trenches | dig in immediately | fighting positions | free |
| T1 | BAR crate + Fortify Tool | first-person, ACE interaction | roadblocks, watchposts, FOB fencing/sandbags | BAR resources (crate bought with €) |
| T2 | AAS composition delivery | call it in, prefab slingloaded to LZ | forward positions, FARPs, mortar pits | `resourcesFIA` (native AAS Antistasi preset) |
| T3 | Construction Yard + RTS placer | top-down, deliberate, slow | HQ concrete walls, towers, hangars | build box budget, at HQ only |

Design rules that follow from this:

- **BAR keeps its current catalogue.** Do not migrate BAR structures into Antistasi's placer or vice versa. They are different interaction models on purpose.
- **Antistasi's existing small build boxes stay as-is** (`Land_PlasticCase_01_medium_F` / `_large_F` / `Land_WoodenCrate_01_F` at 100/500/1500). They remain the untiered general catalogue.
- **The Construction Yard is a capability unlock, not a budget holder.** It gates *what* is buildable; the box you bring still supplies *how much*. This is the C&C model and it is the cheapest to implement, because Antistasi already has a per-entry conditional gate (see §5).
- **War level (`tierWar`) is the progression driver** for build radius, detection scaling, and endgame statics.

### Work packages

| WP | Summary | Blocking? |
|---|---|---|
| WP0 | Discover BAR class names | Blocks WP1–WP3 |
| WP1 | Mod detection flag | Blocks WP2–WP3 |
| WP2 | BAR crates & depot purchasable in garage | — |
| WP3 | Fortify Tool in the Arsenal | — |
| WP4 | Construction Yard + military build tier | — |
| WP5 | War-level scaling of HQ build radius & detection | Depends on WP4 |
| WP6 | War-tier gate on the Statics purchase tab | — |
| WP7 | AAS composition slots (config only, no code) | — |

WP2/WP3 are independently shippable. WP4–WP6 are the base-building arc. WP7 requires no repo changes at all and can be done in parallel by anyone with server admin access.

---

## 2. WP0 — Discover BAR class names (blocking)

BAR has no public source repository and its Workshop page lists no class names. They must be read from the loaded mod. Run this in the debug console in a mission with the full modlist:

```sqf
// CfgPatches entry — needed for the detection guard in WP1
{ diag_log format ["PATCH: %1", configName _x] } forEach
    (("true" configClasses (configFile >> "CfgPatches")) select
        { (configName _x) regexMatch "(?i).*(bar|build|ressource).*" });

// Crates and depot (CfgVehicles)
{ diag_log format ["VEH: %1 | %2", configName _x, getText (_x >> "displayName")] } forEach
    ("(getText (_x >> 'displayName')) regexMatch '(?i).*(ressource|resource|depot).*'"
        configClasses (configFile >> "CfgVehicles"));

// Fortify Tool (CfgWeapons) + how Antistasi classifies it
{ diag_log format ["ITEM: %1 | %2 | itemType %3 | categories %4",
    configName _x,
    getText (_x >> "displayName"),
    (configName _x) call A3A_fnc_itemType,
    (configName _x) call A3A_fnc_equipmentClassToCategories] } forEach
    ("(getText (_x >> 'displayName')) regexMatch '(?i).*fortif.*'"
        configClasses (configFile >> "CfgWeapons"));
```

Record and substitute throughout this document:

| Placeholder | Meaning |
|---|---|
| `<BAR_CFGPATCHES>` | BAR's CfgPatches class name |
| `<BAR_CRATE>` | Resource crate class (there may be several — one per resource type) |
| `<BAR_DEPOT>` | Ressource Depot class |
| `<BAR_TOOL>` | Fortify Tool class |

**Also determine, by inspection in-game:** whether a crate's remaining resources live in an **object variable** or in **cargo** (`itemCargo` / `magazineCargo`). This decides a required flag in WP2. Fill a crate partially, then run `getVariable`/`itemCargo` checks on it.

copyToClipboard str (get3DENSelected "Object" apply { typeOf _x })

Wielded below output while having the 4 BAR crates and the depot selected: 

```
["RessourceCrate_Concrete","RessourceCrate_Metal","RessourceCrate_Sand","RessourceCrate_Wood","RessourceDepot"] 
```

---

## 3. WP1 — Mod detection

**File:** `A3A/addons/core/functions/init/fn_initVarCommon.sqf`

Add next to the existing detection block (~line 114–134, alongside `A3A_hasACE`, `A3A_hasTFAR`, `A3A_hasKAT`):

```sqf
A3A_hasBAR = A3A_hasACE && isClass (configFile >> "CfgPatches" >> "<BAR_CFGPATCHES>");
if (A3A_hasBAR) then { Info("BuildAndRessources detected.") };
```

BAR hard-requires ACE, so gate on both.

**Do not** add BAR to `requiredAddons[]` in any `config.cpp`. It stays a runtime-optional dependency, exactly like ACE, TFAR and KAT. The mission must still load and run cleanly with BAR absent — every change in WP2/WP3 is guarded by this flag.

BAR is not in `fn_modBlacklist.sqf` and does not need to be. For reference, that blacklist only trips on CfgPatches `A3A_ultimate` / `A3A_scrt` for Antistasi variants — the `[A3UE]` mods in the modlist are UnseenKill's prefix, unrelated to Antistasi Ultimate, and will not trigger it.

---

## 4. WP2 — Resource crates purchasable from the garage

### How the system works

Buyable objects are defined in `fn_initUtilityItems.sqf` (server, runs after faction loading, called from `fn_initVarServer.sqf:439`). It produces two globals:

- `A3A_utilityItemList` — ordered class list, used by the UI
- `A3A_utilityItemHM` — hashmap `class -> [class, price, nameKey, iconType, flags]`

`A3A/addons/gui/functions/GUI/fn_buyVehicleTabs.sqf` (~lines 300–461) iterates `A3A_utilityItemList` and builds the **"Other"** tab of the buy-vehicle dialog automatically. **No UI code needs changing.** The container is `A3A_ControlsGroupNoHScrollbars`, so extra rows scroll vertically. Items without an `editorPreview` fall back to a live 3D model render on hover.

Payment is already handled by `fn_buyItem.sqf`: commander spends `resourcesFIA`, other players spend personal `moneyX`, with a 15-second per-player purchase cooldown.

### The change

**File:** `A3A/addons/core/functions/init/fn_initUtilityItems.sqf`

Append after the `A3A_hasACE` block and **before** the name-localization loop:

```sqf
if (A3A_hasBAR) then {
    _items pushBack ["<BAR_CRATE>", 750,  "barcrate", "", ["place","move","rotate","save","noclear"]];
    _items pushBack ["<BAR_DEPOT>", 3000, "bardepot", "", ["cmmdr","place","move","rotate","save","noclear"]];
};
```

If BAR ships multiple crate classes (concrete / wood / sand / metal), add one line each and price them separately.

### Flag reference

Read from `fn_initObject.sqf` and `fn_initObjectRemote.sqf`:

| Flag | Effect |
|---|---|
| `place` | Manual placement via `HR_GRG_fnc_confirmPlacement` rather than a random drop next to the player |
| `move` | Adds the "carry" action |
| `rotate` | Adds the "rotate" action |
| `save` | Registers via `A3A_fnc_rebelVehPlacedWorker` so the object persists across saves |
| `noclear` | **Skips** the cargo wipe |
| `cmmdr` | Commander-only purchase |
| `loot` | Loot-crate behaviour; do not use here |
| `pack` | Requires a matching `A3A_Logistics_Packable` config entry — do not use unless you add one |
| `hugebuild` | Sets ACE cargo size 4 |

> **`noclear` is load-bearing.** `fn_initObject.sqf` calls `clearMagazineCargoGlobal` / `clearWeaponCargoGlobal` / `clearItemCargoGlobal` / `clearBackpackCargoGlobal` on every purchased object unless `noclear` is set. If WP0 established that BAR stores crate contents as cargo, omitting this flag produces a permanently empty crate. If BAR uses an object variable, `noclear` is harmless — keep it either way.

### Stringtable

**File:** `A3A/addons/core/Stringtable.xml`

Add `STR_A3A_Utility_Items_Name_barcrate` and `STR_A3A_Utility_Items_Name_bardepot` next to the existing `STR_A3A_Utility_Items_Name_*` block (~line 16461). A missing key renders the raw key text on the button.

---

## 5. WP3 — Fortify Tool in the Arsenal

Antistasi's arsenal is a limited arsenal: items appear only once unlocked. Two changes are needed — one for new campaigns, one for existing saves — because they take different code paths.

### 5a. New campaigns

**File:** `A3A/addons/core/Templates/Templates/FactionDefaults/RebelDefaults.sqf`

Append `<BAR_TOOL>` to `initialRebelEquipment`, guarded by `A3A_hasBAR`. Follow the conditional pattern used for TFAR items in `Templates/Templates/UNS/UNS_Reb_VC.sqf` (`if (A3A_hasTFAR) then { _initialRebelEquipment append [...] }`).

`fn_initServer.sqf` (~lines 160–180) walks that list on the `_startType == "new"` branch, resolves each class through `jn_fnc_arsenal_itemType`, pushes it into `jna_dataList` with count `-1` (unlimited), and updates the `unlocked*` category arrays.

**Verify** that the rebel templates you actually play don't overwrite `initialRebelEquipment` wholesale — several faction templates define their own list rather than appending to the default.

### 5b. Existing saves

`initialRebelEquipment` is applied only when starting fresh; loads restore `jna_dataList` from the save (`fn_loadServer.sqf` ~lines 46–55). Add a convergent unlock **after** the `if (_startType != "new") ... else ...` block in `fn_initServer.sqf`:

```sqf
if (A3A_hasBAR) then {
    private _tool = "<BAR_TOOL>";
    if !(_tool in unlockedItems) then { [_tool] call A3A_fnc_unlockEquipment };
};
```

`A3A_fnc_unlockEquipment` (`core/functions/Ammunition/fn_unlockEquipment.sqf`) performs the JNA add and updates + publishes the category arrays.

### 5c. Category sanity check

Use the `A3A_fnc_itemType` / `A3A_fnc_equipmentClassToCategories` output from WP0.

- A plain misc item resolves to `["Item","Unknown"]` → categories `["Unknown","Items"]` → arsenal tab CargoMisc. This is fine; `"Unknown"` is a declared category in `fn_initVarCommon.sqf`.
- If it resolves into `Toolkits`, Antistasi's engineer/repair checks may start treating it as a toolkit. Override it in `core/functions/Ammunition/fn_categoryOverrides.sqf`:

```sqf
["<BAR_TOOL>", ["Unknown","Items"]],
```

Unlocking also makes the tool survive custom loadouts — `fn_stripGearFromLoadout.sqf` gates special items on membership in `unlockedItems`.

### 5d. Side effect to decide on

Unlocking places the tool in the CargoMisc pool that `fn_generateRebelGear.sqf` samples for rebel AI loadouts, so AI may spawn carrying Fortify Tools. If undesirable, exclude the class there.

### 5e. Tool overlap

Gruppe Adler Trenches uses an entrenching tool; BAR uses the Fortify Tool. Two tools for adjacent jobs is confusing for players. Either unlock both deliberately and document the split (trenches vs structures), or drop GA Trenches from the loadout path. This is a design call, not a code blocker.

---

## 6. WP4 — Construction Yard and the military build tier

### How the placer works today

- `fn_initBuildableObjects.sqf` reads `buildObjects[]` from the map's `mapInfo.hpp` (e.g. `A3A/addons/maps/Antistasi_Altis.Altis/mapInfo.hpp:20`) into `A3A_buildableObjects`, and derives `A3A_buildingPriceHM`.
- Entries are `{className, price}` or `{className, price, ability}`.
- The third field is a **conditional gate**, currently used exactly once: `{"a3a_helipad", 1500, "helipad"}`. In `A3A/addons/gui/functions/GUI/fn_teamLeaderRTSPlacerDialog.sqf` (~line 103) the button is disabled unless the player is within 75 m of a friendly-held marker.
- The catalogue is **global per map** — box size determines budget only, not what's offered.
- `fn_lockBuilderBox.sqf` moves the box's `A3A_itemPrice` into `A3A_build_money`, and **deletes the box when the budget reaches zero**.
- Placement is client-side ghost objects; on exit `fn_placeBuilderObjects.sqf` spawns build sites (pallets / cinder blocks / planks chosen by price) with a hold action, hold time `1.2 * sqrt(price)` (×0.75 within 100 m of HQ) and a 20-minute timeout. `fn_buildingComplete.sqf` then swaps the site for the real structure and registers it into the garrison.

### 6a. Add the `basetier` gate

**File:** `A3A/addons/gui/functions/GUI/fn_teamLeaderRTSPlacerDialog.sqf`

Extend the existing `_ability` handling (the block that currently special-cases `"helipad"`) with a `"basetier"` case. Disable the button and set a tooltip unless **both**:

1. a friendly Construction Yard object exists within the current HQ build radius, and
2. the player is inside the HQ build area.

Reuse the shape of the helipad check — it already does a marker-proximity test and `ctrlEnable false` + `ctrlSetTooltip`.

Add a stringtable key alongside `STR_antistasi_teamleader_placer_cannotBuildHelipad`.

### 6b. Tag the military catalogue

**Files:** `A3A/addons/maps/Antistasi_<map>.<map>/mapInfo.hpp` for each map you play.

Append tier-3 entries with the `basetier` ability. Given the modlist (vanilla + Contact structures; **no** CUP Terrains), suggested starting catalogue:

```cpp
// --- Military tier (requires Construction Yard) ---
{"Land_Cargo_Tower_V1_F",      3000, "basetier"},
{"Land_Cargo_Patrol_V1_F",     1200, "basetier"},
{"Land_Cargo_House_V1_F",       900, "basetier"},
{"Land_HBarrierTower_F",        800, "basetier"},
{"Land_HBarrierBig_F",          250, "basetier"},
{"Land_HBarrier_5_F",           120, "basetier"},
{"Land_CncWall4_F",             150, "basetier"},
{"Land_CncBarrierMedium4_F",    100, "basetier"},
{"Land_Razorwire_F",             60, "basetier"},
{"Land_Net_Fence_4m_F",          40, "basetier"}
```

`Land_MilitaryWall_01_*_F` (Contact DLC) is a good addition if all players own Contact — verify with `isClass` before adding, since Antistasi's map configs are shared. Hangars and larger cargo houses are reasonable later additions once pricing is proven.

**Do not** put sandbags, bag fences or small barricades in this tier. Those stay in the untiered catalogue (T1 overlap with BAR is intentional and fine).

### 6c. The Construction Yard object itself

Add it as a **utility item** so it is purchased from the garage "Other" tab like any other object.

**File:** `A3A/addons/core/functions/init/fn_initUtilityItems.sqf`

```sqf
_items pushBack ["<YARD_CLASS>", 5000, "constructionyard", "", ["cmmdr","hqonly","place","rotate","save","noclear"]];
```

Suggested `<YARD_CLASS>`: `Land_Cargo_House_V1_F` (reads as a site office), or `Land_Shed_Big_F` / a crane object for a more literal C&C read. It should **not** carry the `move` flag — a yard that can be picked up and carried defeats the point.

**New flag `hqonly`.** Implement in `A3A/addons/core/functions/UtilityItems/fn_buyItem.sqf`, inside the `_fnc_placed` callback, before the funds check:

```sqf
if ("hqonly" in _flags && { _item distance2D (getMarkerPos "Synd_HQ") > 75 }) exitWith {
    [_titleStr, localize "STR_A3A_Utility_Items_HQ_Only"] call A3A_fnc_customHint;
    deleteVehicle _item;
};
```

Add the stringtable key. Use the same radius source as WP5 rather than a literal 75 once WP5 lands.

**Also enforce one per campaign.** Reject the purchase if a yard already exists (check `nearestObjects` around HQ, or a server variable set on placement). Two yards is meaningless and doubles the proximity checks.

### 6d. HQ relocation

`fn_relocateHQObjects.sqf` teleports a fixed set of named globals (`fireX`, `boxX`, `mapX`, `flagX`, `vehicleBox`) when Petros moves. The Construction Yard is **not** in that list and will be left behind.

Two options — pick one and document it:

- **Follows HQ:** add the yard to `fn_relocateHQObjects.sqf`. Simple, forgiving.
- **Stays and must be rebuilt:** better tension, but brutal if players are forced to relocate at high war level. If chosen, refund a percentage on HQ move.

Recommendation: follows HQ. Losing the entire military tier on a forced HQ move is a punishment disproportionate to the mistake.

---

## 7. WP5 — War-level scaling

`tierWar` is a 1–10 global computed in `core/functions/OrgPlayers/fn_tierCheck.sqf` from captured-site points and `publicVariable`'d on change (WT4 ≈ 8% of map points, WT8 ≈ 42%, WT10 = 70%). It is already the standard progression gate across the codebase.

### 7a. Scale the HQ build radius

**File:** `A3A/addons/core/functions/UtilityItems/fn_initObjectRemote.sqf`, line ~68

Currently the only call site:

```sqf
{ [_this#0, 75, _this#0] spawn A3A_fnc_buildingPlacerStart },
```

For a box used within the HQ area, centre on the HQ marker and scale the radius:

```sqf
private _radius = 75 + 15 * (tierWar - 1);   // 75 m @ WT1 → 210 m @ WT10
```

Introduce a helper (e.g. `A3A_fnc_hqBuildRadius`) rather than duplicating the formula — WP4's `hqonly` check and WP5's marker logic both need it.

### 7b. The marker coupling problem — do not skip this

`Synd_HQ` is created at `[75,75]` in `fn_initServer.sqf:40`. `fn_buildingComplete.sqf` resolves a finished structure's owner marker via `A3A_fnc_getMarkerForPos`, which only returns `Synd_HQ` if the position is **inside that marker**. Anything outside falls into `A3A_buildingsToSave` — still persisted, but **not** in the HQ garrison and **not** counted by `A3A_fnc_calcBuildingCosts`.

Consequence: if build radius grows past 75 m while the marker stays at 75 m, everything in the outer ring becomes invisible to the detection calculation. Players get free stealth fortification, and the WP5c scaling below silently stops working.

Two fixes:

- **Preferred (low blast radius):** in `fn_buildingComplete.sqf`, before falling back to `A3A_buildingsToSave`, explicitly assign to `Synd_HQ` any building within the current HQ build radius.
- **Alternative (higher risk):** scale `Synd_HQ` marker size with `tierWar` in lockstep. This is more "correct" but the marker feeds `fn_getMarkerForPos` precedence over overlapping markers, `fn_spawnGarrisonSquads`, `fn_garrisonLocal_zoneCheck` capture radius, `fn_blackout`, and `fn_placeIntel`. A 210 m HQ marker may start swallowing adjacent town markers. Requires an audit; do not do this casually.

### 7c. Scale the detection radius

**File:** `A3A/addons/core/functions/Builder/fn_calcBuildingReveal.sqf` (four lines)

```sqf
#define MAX_COST 2500
private _cost = ["Synd_HQ"] call A3A_fnc_calcBuildingCosts;
private _reveal = 500 + ((_cost min MAX_COST)/5);
A3A_HQDetectionRadius = _reveal;
```

Consumed by `fn_requestSupport.sqf` as `A3A_HQDetectionRadius - 250 + random 500`.

Make the cap scale so late-game fortification stays meaningful instead of capping out instantly:

```sqf
private _maxCost = 1000 + 400 * tierWar;     // 1400 @ WT1 → 5000 @ WT10
private _reveal = 500 + ((_cost min _maxCost)/5);
```

Early HQs cap fast — build small, stay hidden. A WT10 HQ can absorb a real base before saturating. Recalculation already fires on garrison add/remove and HQ move; add a recalc on `tierWar` change in `fn_tierCheck.sqf`.

> Rejected alternative: scaling the **divisor** (`_cost / (5 + tierWar)`) so fortification draws proportionally less attention late. This erases the stealth-vs-fortify tradeoff exactly when players finally have the money to engage with it.

### 7d. Bounding circle

`fn_buildingPlacer.sqf` draws exactly 36 `Sign_Sphere100cm_F` markers around the radius. At 210 m that is one sphere every ~37 m, which reads as scattered dots rather than a boundary. Scale the count with radius (target ~10 m spacing, cap around 120 spheres for performance).

---

## 8. WP6 — War-tier gate on the Statics tab

**File:** `A3A/addons/gui/functions/GUI/fn_buyVehicleDialog.sqf`, ~lines 102–105

```sqf
private _statics =
(A3A_faction_reb get 'staticMGs') +
(A3A_faction_reb get 'staticMortars') +
(A3A_faction_reb get 'staticAA') +
(A3A_faction_reb get 'staticAT');
```

This is a flat concatenation of the rebel template arrays with **no war-tier filter whatsoever**. Everything in those arrays is buyable from campaign start.

This matters for the endgame goal: Vanilla CRAM does not add a class — it makes the vanilla Praetorian 1C (`B_AAA_System_01_F`) intercept incoming shells. The moment a Praetorian lands in `staticAA` it is purchasable at war level 1, which is exactly wrong for a capstone base-defence asset.

Add a class → minimum-tier map and filter `_statics` against `tierWar`. Follow the existing gating convention (`fn_SUP_artilleryAvailable.sqf` uses WT5, `fn_SUP_orbitalStrikeAvailable.sqf` uses WT8, `fn_mrkWIN.sqf` blocks airbase capture below WT3).

Suggested placement: a `staticMinTier` hashmap in the rebel template alongside the static arrays, so it stays faction-configurable rather than hardcoded in the GUI. Suggested value for the Praetorian: **WT7**.

Disable rather than hide the buttons, with a tooltip naming the required war level — players should be able to see what they are working toward.

---

## 9. WP7 — AAS composition slots (configuration only)

No repository changes. This is CBA Addon Options work on the server, but it is part of the same design and should be specified alongside.

### What AAS already does

From `github.com/KOLOVIAN/Adaptative-Arma-Supports-Core`:

- `addons/core/functions/fn_setEconomyPreset.sqf` **preset 1 is Antistasi**. It reads `server getVariable "resourcesFIA"` and deducts with `[0, -_cost] remoteExec ["A3A_fnc_resourcesFIA", 2]`. Set `AAS_Econ_Preset_Core` to 1 and AAS spends the faction treasury natively — no glue code.
- `addons/logistics/functions/fn_initsettings.sqf` defines **10 composition slots**, each with `Name`, `Code`, `Init`, `Mult` settings. Shipped defaults: 1 Watchtower, 2 Checkpoint/FOB, 3 Mortar Position, 4 FARP, 5 Drone Station, **6–10 empty**.
- Cost = `AAS_LOG_Cost_Base_Antistasi` (default 1000) × the slot's `Mult`. Global 60 s airspace cooldown plus a per-item cooldown (`AAS_LOG_Cooldown_Delivery`, default 600 s).
- Delivery is a slingload run by a heavy helicopter to the chosen LZ, then unpacked at the anchor point.

> Compositions live in the `aas_logistics` PBO, not `aas_core`. The standalone Workshop module items are marked deprecated, which is consistent with them now shipping inside the AAS Core package. **Verify** that CBA Addon Options shows an "AAS - Logistics" category on the server before designing slots.

### Composition array format

Confirmed by reading `fn_serverdelivery.sqf` (~lines 425–470). Each element:

```
[className, relPos, relDir, parentIdx, isSimple, textures, initCode, inventory]
```

Only the first three are required. Positions are relative to the anchor; the anchor's direction is applied to the whole composition. `isSimple` uses `createSimpleObject` (cheap, non-interactive — good for walls and clutter). `initCode` runs on the spawned object after a 2 s delay, which is useful for locking statics, setting textures, or configuring CRAM targeting mode.

To generate the array, build the composition in Eden, then run this in the **3DEN debug console** with all objects selected and the intended anchor object selected first:

```sqf
private _objs = get3DENSelected "Object";
private _origin = getPosATL (_objs # 0);
copyToClipboard str (_objs apply {
    [typeOf _x, (getPosATL _x) vectorDiff _origin, getDir _x]
});
```

Paste directly into the slot's `Code` editbox. Verify the first entry is `[..., [0,0,0], ...]`.

### Slot plan

Keep the five shipped defaults. Tune their `Mult` values against Antistasi economy scale — at base 1000, a Watchtower at `Mult` 1.0 costs €1000, which is roughly one small build box plus change and feels about right; a FARP should be considerably more.

Fill slots 6–10 as the endgame tier. Design constraints: each must be slingloadable as a single anchor drop, and must not duplicate what T1/T3 already do well.

| Slot | Name | Contents | Notes |
|---|---|---|---|
| 6 | Air Defence Battery | `B_AAA_System_01_F` (Praetorian, CRAM-enabled) + `Land_HBarrier_5_F` revetment + `Land_PortableGenerator_01_F` + `Land_BagFence_Round_F` | Gate behind the same war tier as WP6's static gate. Use `initCode` to set CRAM targeting mode. Highest `Mult` in the set. |
| 7 | Hardened Ammo Depot | `Land_Cargo_House_V1_F` + `Box_NATO_Ammo_F` / `Box_NATO_AmmoOrd_F` + `Land_HBarrierBig_F` blast walls + camo net | Pair with Antistasi's ammo container so it actually resupplies |
| 8 | Comms Station | `RuggedTerminal_01_communications_F` + `SatelliteAntenna_01_Olive_F` + `OmniDirectionalAntenna_01_olive_F` + `Land_PortableSolarPanel_01_sand_F` | Thematically the AAS "tent" — the thing that justifies calling supports |
| 9 | Vehicle Service Point | `Land_RepairDepot_01_green_F` + `Land_FlexibleTank_01_forest_F` + `Land_Pallet_MilBoxes_F` + `Land_Crane_F` clutter | Overlaps Antistasi's repair/refuel utility items — price it as a convenience, not a shortcut |
| 10 | *(reserve)* | — | Leave empty for a map-specific or event composition |

Reuse the object vocabulary already present in the shipped defaults (`Land_TentDome_F`, `Land_BagFence_Round_F`, `Land_CzechHedgehog_01_new_F`, `Land_Razorwire_F`, `CamoNet_BLUFOR_F`, `Land_Laptop_02_unfolded_F`) so the new slots read as the same faction's kit.

### Overlap to resolve

`[A3UE] Built-in Radio Supports` and AAS are both support-calling frameworks. Running both gives players two menus for the same job, and only AAS has the Antistasi economy hook. Pick one as the canonical support system.

---

## 10. File change index

| File | WP | Change |
|---|---|---|
| `core/functions/init/fn_initVarCommon.sqf` | 1 | Add `A3A_hasBAR` |
| `core/functions/init/fn_initUtilityItems.sqf` | 2, 4 | BAR crate/depot entries; Construction Yard entry |
| `core/Stringtable.xml` | 2, 4 | Item name keys, HQ-only hint, basetier tooltip |
| `core/functions/UtilityItems/fn_buyItem.sqf` | 4 | `hqonly` flag enforcement, one-yard-per-campaign |
| `core/functions/UtilityItems/fn_initObjectRemote.sqf` | 5 | Scaled/HQ-centred build radius (line ~68) |
| `core/Templates/Templates/FactionDefaults/RebelDefaults.sqf` | 3 | Fortify Tool in `initialRebelEquipment` |
| `core/functions/init/fn_initServer.sqf` | 3 | Convergent unlock for loaded saves |
| `core/functions/Ammunition/fn_categoryOverrides.sqf` | 3 | Only if WP0 shows bad auto-classification |
| `core/functions/Builder/fn_calcBuildingReveal.sqf` | 5 | Tier-scaled `MAX_COST` |
| `core/functions/Builder/fn_buildingComplete.sqf` | 5 | HQ garrison assignment within build radius |
| `core/functions/Builder/fn_buildingPlacer.sqf` | 5 | Bounding circle sphere count |
| `core/functions/Base/fn_relocateHQObjects.sqf` | 4 | Yard follows HQ (if chosen) |
| `core/functions/OrgPlayers/fn_tierCheck.sqf` | 5 | Recalc reveal on tier change |
| `gui/functions/GUI/fn_teamLeaderRTSPlacerDialog.sqf` | 4 | `basetier` ability gate |
| `gui/functions/GUI/fn_buyVehicleDialog.sqf` | 6 | War-tier filter on `_statics` |
| `maps/Antistasi_<map>.<map>/mapInfo.hpp` | 4 | `basetier` catalogue entries, per map |

---

## 11. Testing checklist

**Without BAR loaded** (regression guard — run this first):

- [ ] Mission starts, no RPT errors referencing `A3A_hasBAR` or missing classes
- [ ] "Other" tab shows exactly the pre-existing item set
- [ ] Arsenal contains no Fortify Tool entry
- [ ] Existing saves load cleanly

**With the full modlist:**

- [ ] Crate appears in "Other" with correct name, price and preview
- [ ] Purchase deducts from `resourcesFIA` as commander and `moneyX` as a regular player
- [ ] **Crate still holds its resources after purchase** (the `noclear` check)
- [ ] Fortify Tool present in Arsenal on a new campaign
- [ ] Fortify Tool present in Arsenal on a **save loaded from before these changes**
- [ ] Crate + tool actually build BAR structures in-game
- [ ] Crate survives a save/load cycle — and note whether its **remaining resource amount** survives (see risks)
- [ ] Yard cannot be placed away from HQ; second yard is rejected
- [ ] `basetier` entries are greyed out with no yard, enabled with one
- [ ] Build radius visibly grows between two different `tierWar` values (force via debug console)
- [ ] A structure built in the outer ring is counted by `A3A_fnc_calcBuildingCosts`
- [ ] `A3A_HQDetectionRadius` changes as expected at low vs high tier
- [ ] Praetorian is unavailable in the Statics tab below its gate tier, available above
- [ ] AAS composition delivery deducts `resourcesFIA` and unpacks correctly at the LZ

---

## 12. Known risks

1. **BAR crate contents are not saved.** Antistasi's save system persists class and position (`fn_saveLoop.sqf`, `fn_convertSavedStatics.sqf`). A crate's remaining resource amount is BAR-internal state and will almost certainly reset on load. If that matters, it needs a custom hook — read the value on save, reapply on load. Confirm the actual behaviour in testing before deciding whether to build it.
2. **BAR must be loaded server-side.** Crates are created with `createVehicle` on the server, not just previewed on clients.
3. **Three parallel economies.** Antistasi € buys the crate; BAR resources are consumed inside it; AAS spends `resourcesFIA` directly. Price these against each other deliberately — the native large build box at €1500 is the reference point.
4. **Marker-size changes are high risk.** If WP5b's alternative path is taken, budget real time for the audit. The preferred path exists specifically to avoid this.
5. **Enhanced Movement changes wall semantics.** Players can vault obstacles that AI cannot path over. High concrete walls will produce asymmetric defence — good for holding a base, but do not assume walls block players.
6. **Workshop availability.** The BAR Workshop page currently displays a removal/incompatibility notice banner. Confirm the mod still downloads and loads before committing to it as a hard part of the modlist.
