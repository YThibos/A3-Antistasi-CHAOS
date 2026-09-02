# Antistasi CHAOS — Research & TODO

Working document. The brainstorm transcript that seeded this file has been processed
into the sections below and removed; nothing of substance from it was dropped.

Status keys: **[DONE]** shipped and in the tree · **[TODO]** agreed, not built ·
**[IDEA]** not decided · **[OPEN]** needs a call before it can be built.

---

## 1. Supply network

### 1.1 Iteration 1 — shipped

- **[DONE]** Shared influence core. `A3A_fnc_influenceContext` owns zone collection,
  per-type radii, the training factor and every model constant;
  `A3A_fnc_influenceAt` is the point query. `fn_computeInfluenceZones` (client raster)
  and `A3A_fnc_computeSupplyGraph` (server) are both built on it, so the drawn border
  and supply connectivity cannot drift apart.
- **[DONE]** `A3A_CHAOS_influenceRange` / `influenceReach` promoted to server-forced
  global settings. Geometry is global, presentation stays per-client.
- **[DONE]** Supply graph. Markers are nodes; same-side zones within
  `(R(A)+R(B)) * reachMult` are candidate edges; a candidate survives only if every
  sample along the corridor is owned by that side. Reach is a BFS from the side's root
  (`Synd_HQ` for the player). Rebuilt debounced on territory events, forced on the
  income tick.
- **[DONE]** Player supply edges drawn as dashed lines on every overlay-capable map.
- **[DONE]** Enemy factions scale by their own connectivity —
  `A3A_fnc_supplyRateMultiplier` multiplies Occupant and Invader attack *and* defence
  rates, stacking with the existing no-airport penalty.
- **[DONE]** BAR crates are empty freight (250 credits); the BAR resource depot is
  gated behind the Construction Yard; connected factories deliver material into the
  depots inside the HQ build radius each income tick, clamped per depot.

**Correction to carry forward:** enemies received a rate *multiplier*, not extra cash
income. There is no separate enemy cash pool. Anything designed against the "extra
income" reading is designed against a baseline that does not exist.

### 1.2 Iteration 2 — replenishment gating

The core mechanic. Enemy garrisons sit at maximum, get attrited when attacked, and
refill over time; the supply graph gates only that refill.

- Connected marker → regenerates garrison at the normal rate.
- Severed marker → does not regenerate at all.

This makes hit-and-retreat consequential: cut the line first, then attrit, and it stays
attrited.

**[TODO]** Gate fulfilment, not the pool. The pool is faction-wide but spending must be
gated by location — an unreachable marker cannot be paid for however full the pool is.

**Verified against the tree (2026-09-02):**

| Claim | Result |
|---|---|
| Defence pool pays for reinforcements | **CONFIRMED** — `fn_reinforceSide.sqf:22` spends 20% of `A3A_resourcesDefenceOcc/Inv` per pass |
| There is a single hook to gate on | **CONFIRMED** — `_reinfMarkers` at `fn_reinforceSide.sqf:33`; filter it by connectivity and the feature is done |
| Garrison tracks "requested units" that died | **WRONG, but harmless** — the deficit is *derived* each pass (`_par - _cur` from `A3A_garrisonSize` vs `garrison get "troops"`), not stored. Attrition still persists as the gap, so restoring a line lets the backlog fill in. Do not design anything needing to know *when* or *how* units were lost. |
| Edge length is uncapped | **WRONG** — cap is `(R(A)+R(B)) * reachMult`: ~4 km outpost-to-outpost, ~5.6 km airfield-to-airfield at Altis defaults |

`fn_reinforceSide` already excludes markers for three reasons (`forcedSpawn`, an enemy
airfield within 1000 m, recent damage > 50 → "use QRFs instead"), so a connectivity
filter follows an established pattern rather than inventing one. Note the recent-damage
exclusion already suppresses reinforcement briefly after a raid; supply severing makes
that persistent rather than duplicating it.

**[DONE — decided]** Keep both gates (pool multiplier *and* fulfilment gating) and
soften the floor: `A3A_CHAOS_supplyRateFloor` default raised 0.5 → 0.75.

**[OPEN]** Maximum edge length. Deferred deliberately — retest with real markers on a
real map before tuning. The concern is that one long airfield-to-airfield link keeps an
isolated pocket alive and makes severing feel arbitrary. Lever is either a hard metre
cap on top of the radius-derived one, or retuning `influenceReach`.

### 1.3 Graph membership

**[TODO]** Outposts and airfields IN as nodes, alongside resources and factories.
Roadblocks and watchposts OUT.

Rationale: roadblocks and watchposts are the player's influence-shaping tools, placed
specifically to sever corridors. If they were also nodes they would repair the network
they exist to cut — one object doing two contradictory jobs. They keep projecting
influence either way; this is about graph topology, not the field.

Current state: `A3A_fnc_influenceContext` collects `markersX + outpostsFIA + controlsX`,
so every zone is currently both an influence contributor and a graph node. The split is
small and local.

### 1.4 Enemy supply rooted at map edges

**[IDEA]** Root Occupant and Invader networks at map-border entry points rather than at
an HQ-equivalent. Models reinforcement flowing in from off-map, which is what an
occupying army is, and makes a lateral thrust to a border or coast meaningful — cutting
across the corridor severs everything behind it.

Air and sea entry needs no special case: player watchposts and roadblocks enforcing
influence are typically manned with AA and statics, so overflying a cut already carries
real risk.

Current state: enemy roots are "best owned airfield, else best outpost, else largest
holding", re-picked every rebuild.

### 1.5 Deliberately not decided

- **[OPEN]** Enemy supply visibility. The server does not publish enemy edges — handing
  every client a live map of the enemy network with no scouting is a decision nobody has
  made. Data exists server-side; wiring intel (captured laptop, interrogation) is a
  self-contained follow-up.
- **[OPEN]** Depots as a failure surface. `fn_chooseAttack` targets *markers*, so a
  depot is only ever attacked incidentally and depot destruction currently severs
  nothing. Corridor severance is what actually cuts lines. Making depot raids matter
  needs a mission type added to the attack director.

---

## 2. Tiered resources and factories

The economy's own split is the tier ladder: in `fn_resourcecheck`, resources are the
**additive** cash term and factories the **multiplier**. So resource tiers scale the
additive term and factory tiers scale the multiplier — no new currency, no change to
the shape of the existing formula.

### 2.1 Tier 1 — the supply warehouse

**[TODO]** A mission picks a player-owned resource or factory that has no tier yet.
The player brings a container (`Land_Cargo10_blue_F` as the base — flatbed-loadable and
sling-loadable), drops it at the site, and builds a warehouse (`Land_Warehouse_03_F`)
from it.

Build interaction: reuse the existing placer chain so the structure can be *aligned*
before it is committed, because it persists —
`A3A_fnc_buildingPlacerStart` (RTS camera, radius, builder box) → plank object →
`BIS_fnc_holdActionAdd` "Build" via `A3A_fnc_addBuildingActions` → `A3A_fnc_buildingComplete`
on the server. The delivered container acts as the builder box with a one-item
catalogue. A scroll-wheel action is the fallback only if the placer proves impractical.

Naming: call this the **supply warehouse**, never "depot" — "depot" already means the
BAR `RessourceDepot` at HQ in iteration 1, and the collision would be permanent.

### 2.2 Tier 2 — power

**[TODO]** Deliver a `Land_PowerGenerator_F` to a tier-1 site. Stands in for heavy
machinery (Arma has no excavator or drill-rig asset worth using) and reads naturally as
"more power for the machines".

### 2.3 Tier 3

**[IDEA]** On-site processing for resources, retooling for factories. Not specified yet.
Original sketch: tier-3 factories require a direct line to a tier-3 resource, which is
the supply chain actually biting.

### 2.4 Traps that constrain any tier ladder

1. **The economy is normalised per map.** `fn_initZones` sets
   `A3A_rebelCashResMult = 1500 / count resourcesX` and
   `A3A_rebelCashFactMult = 1.4 / count factories`, so all resources on any map are
   collectively worth 1500/tick and all factories +140%, whatever the count. Tier
   multipliers on both terms **compound**: a fully tiered map is not 3x income, it is
   closer to 3 x 3. Any ladder needs an explicit ceiling and an explicit inflation
   target.
2. **New markers inflate and can demote your war tier.** Those multipliers are computed
   once at init, so a marker added mid-campaign takes a full undiluted share; and
   `fn_tierCheck` derives `_totalPoints` from the same counts, so adding one can
   retroactively *lower* `tierWar`. Any dynamic-site feature must keep surveyed sites in
   a separate list excluded from `tierCheck`.
3. **Tier state is new persistent state.** It must go into the save/load path under
   `A3A/addons/core/functions/Save/` or it silently resets on reload. Iteration 1
   introduced no new saved state precisely because the graph is derived; tiers end that.

---

## 3. Marker types

**[IDEA]** Give resource and factory markers sub-types so each has a purpose.

Finding: the labels seen on Altis ("Storage", "Quarry", "Mine", "Fotia") are **terrain
Location names from the map itself**, not Antistasi data. `fn_localizar` generates its
own label ("Resource of «nearest city»"), and the only typing that exists is
`fn_initMarkerTypes` setting one flat `"resource"` / `"factory"` type. Sub-types are
therefore greenfield.

Natural home: derive them once at init from a `nearestLocations` / `nearestObjects` scan
in `fn_initMarkerTypes` — the same mechanism the survey idea below needs, so build it
once and use it twice.

**[IDEA]** Survey system for unmarked sites. Some map locations look like resource or
factory sites (industrial pipes, chimneys, warehouses, stadium assets, dam masonry) but
carry no marker — the Stadium factory text and the Xirolimni Dam are examples. A
"Survey" action could scan a 50–100 m radius with `nearestObjects` for those classnames,
check `isFlatEmpty` for clearance, and register a new site. Subject to trap 2 above.

**[IDEA]** Per-type gathering, Overthrow-style but lighter: a resource type accumulates a
specific material over time, on top of the existing cash tick, which is then spent on
upgrades or carried to a factory to be processed into something more valuable. Interim
step that needs no sub-types: **let the linked resource decide which BAR material a
factory ships, and the factory decide the rate.**

---

## 4. Enemy balance

### 4.1 What the enemy already has

Audited against the tree, 2026-09-02.

**Economic**

1. **Their rate rises as you win.**
   `A3A_balancePlayerScaleBase = (players^0.8 + 1 + tierWar/4) / 6`
   (`fn_aggressionUpdateLoop.sqf:43`). War tier is *your* territory, so every marker you
   take raises their income rate. This is a rubber band pointed the wrong way, and it is
   the single most important number to know before balancing anything territorial.
2. **Aggression multiplies both pools** — `_aggroMul = 1.0 + aggression/200`, and
   aggression is driven by your actions.
3. **Attack and defence self-balance** — `_shift` moves budget between the pools based on
   how full defence is, so they cannot stall by over-saving.
4. **They start owning everything** — every marker at par garrison, nothing to rebuild.
5. **Destroyed sites self-repair** — 5%/tick, and 20%/tick for Invader-held resources
   (`fn_resourcecheck.sqf:149-151`).

**Military**

6. **Reinforcement ignores logistics entirely** — 20% of the defence pool dispatched to
   any owned marker with no travel time modelled; the code comment says as much. This is
   the largest structural gift and exactly what §1.2 removes.
7. **City garrisons regenerate on a 60-second loop** independent of the defence pool:
   `sqrt(pop) * sqrt(playerScale) / 120` per minute.
8. **Unit skill scales with war tier and player count** —
   `_baseSkill = 0.1*skillMul + 0.07*players^0.5 + 0.01*tierWar` (`fn_NATOinit.sqf:80`),
   plus NVG availability gated on `random 5 > tierWar`.
9. **HQ intel accumulates and decays slowly** — 0.01/tick current, 0.1/tick stale, and
   every support call you make adds `_hqSpot * (100 + aggression)/400`.

### 4.2 Early passivity is designed, and is being kept

`fn_chooseAttack.sqf:48-51` scales **rebel** target weights by
`(0.4 + tierWar/30 + aggro/200) / _rebWeightMul` before the other enemy faction's
targets are appended. At war tier 1 with no aggression that is ~0.4, so early game they
are deliberately biased toward fighting each other. It climbs past 1.0 as tier and
aggression rise.

**Decision: keep it.** Early passivity toward the player is wanted — let them fight each
other first.

### 4.3 A death spiral nobody designed

`fn_updateMinorSites.sqf:50` sizes each side's wanted camp/roadblock count by how many
main markers it owns. Lose markers → fewer minor sites → less influence projected →
worse connectivity → lower rate → fewer markers. Iteration 1 made an existing spiral
steeper. Watch it in testing; it is the main argument for a higher rate floor.

### 4.4 Boost ideas — recorded, not implemented

Listed smallest first. None of these are agreed; they exist so the option is on the
table if testing says the enemy is too soft.

1. **[IDEA — declined for now]** Raise the early-game rebel-target weight floor from
   `0.4` to ~`0.55`. Explicitly not wanted: see §4.2.
2. **[IDEA]** Early-tier Occupant defence-rate bonus that decays, e.g.
   `× (1.15 - tierWar/100)` — strongest when entrenched, fading as the insurgency
   matures. Counteracts the backwards rubber band in §4.1.1. Slots in beside the
   no-airport line.
3. **[IDEA]** Soften the Invader no-airport penalty from ×0.2 to ~×0.35 so a beachhead
   is survivable and the three-way war stays live longer.
4. **[IDEA]** Supply-gate city reinforcement too. It currently bypasses the defence pool
   entirely on a 60-second loop — the largest hole in §1.2's fiction. This is a *nerf*
   dressed as consistency; weigh separately.
5. **[IDEA]** Decay HQ intel more slowly at high war tier, so late game they close in.

---

## 5. Tweaks and fixes

- **[TODO]** Garrison radius at max tier. `fn_garrisonVehicleRadius.sqf` uses
  `30 * _tier` — 30 m at tier 1 to 300 m at tier 10, and 300 m is too big (it is a
  radius, not a diameter). Proposed `15 * _tier` caps at 150 m but gives **15 m at tier
  1**, which is smaller than many roadblock footprints — a static parked 20 m away would
  stop counting. `40 + 11 * _tier` (51 m → 150 m) keeps the cap while staying usable
  early.
- **[TODO]** Custom keybind to toggle the influence / border overlay on and off. CBA
  keybind; the setting `A3A_CHAOS_influenceOverlayEnabled` already exists and is read
  per-frame, so the binding only has to flip it.
- **[TODO]** AAS (Antistasi Support System) — the orange-smoke bypass lets supports be
  called without buying the tents that are supposed to gate them. High priority bug fix.
  Then gate support tents behind the Construction Yard, and revisit support pricing
  against the scaled economy.

---

## 6. Longer-range direction

- **[IDEA]** Raw materials gate automated base defences (C-RAM, Patriot-style SAM), with
  the enemy scaling hard against it, so the late game is big set-piece fights rather than
  mop-up.
- **[IDEA]** Power as a *capability gate*, not a resource. The map's power plants are too
  rare to depend on, so let commanders build local generators inside a base; destroy the
  generators and the SAMs go offline. This matches the fork's existing identity —
  Construction Yard, ACC, helipad are all capability gates, and `fn_hasConstructionYard`
  is the template (class + object variable, `allMissionObjects` scan).
- **[IDEA]** Endgame base-vs-base: once a tier-3 player base exists, enemy commanders
  start building fortified bases of their own. Flagged as by far the largest item here —
  a new AI construction subsystem, not a tweak.
- **[IDEA]** Frontline-specific missions and events. Nothing settled.

### Design constraint

**No new resource types.** Reuse BAR's four raw materials. Keeps the logic simple and,
more importantly, keeps it something the AI can reason about without a parallel economy.

### Resolved and closed

Interior-versus-border garrison strength was considered and dropped: it is not a supply
problem. Supply sets the budget, not its distribution.
