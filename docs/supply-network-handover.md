# Supply network — state and handover

Written 2026-08-31 by a Claude Code remote session working from `AGENTS.md`
(hard rules, skills under `.claude/skills/`, `Tools/sqfcheck` as the gate).
Branch: `claude/antigravity-conversation-exploration-og7gql`.

Design decisions behind this were taken in conversation with the project owner;
this file records what landed, what it assumes, and what is deliberately left.

## What landed

| Piece | Function | Runs on |
|---|---|---|
| Shared field context | `A3A_fnc_influenceContext` | anywhere |
| Point query | `A3A_fnc_influenceAt` | anywhere |
| Supply graph | `A3A_fnc_computeSupplyGraph` | server |
| Debounced rebuild | `A3A_fnc_refreshSupplyGraph` | server |
| Enemy rate modifier | `A3A_fnc_supplyRateMultiplier` | server |
| Factory production | `A3A_fnc_factoryDepotTick` | server |

Published state: `A3A_supplyEdges` and `A3A_supplyConnected` (public, player
side only), `A3A_supplyRatios` (server-side hashmap, side -> connected/owned),
`A3A_supplyGraphMs` (diagnostic).

**No new persistent state was introduced.** The graph is derived and rebuilt on
every territory change and every income tick, and BAR depot stock was already
saved by `fn_barSave`. That is why nothing under `functions/Save/` changed. The
moment per-marker tiers are added (see below) that stops being true and hard
rule 8 applies.

## What was NOT verified

Everything below the syntax level. `Tools/sqfcheck` is clean on all changed
files and the stringtable parses, and that is the entire extent of the
verification. Specifically untested:

- **Any gameplay behaviour whatsoever.** No mission was run.
- **Cost.** `A3A_supplyGraphMs` is logged for exactly this reason — watch it in
  the RPT on a populated Altis campaign. The candidate scan is O(n^2) in
  squared-distance tests per side and the corridor sampling is budgeted at
  60 000 samples, but neither figure is measured.
- **Locality and JIP.** The graph is server-built and published by
  `publicVariable`, so a JIP client gets the last published value — but a client
  that joins before the first rebuild has `A3A_supplyEdges` undefined until the
  next territory event or income tick. The draw handler defaults to `[]`, so it
  draws nothing rather than erroring; whether that gap is noticeable in practice
  is unknown.
- **BAR's depot capacity variable.** `A3A_CHAOS_barDepotCap` is this fork's own
  ceiling. Only `transferDepotToCrate`'s return exposes BAR's own capacity, and
  reading it would mean calling that function for its side effects. If BAR's own
  cap is lower it will refuse the surplus on transfer, which is safe but means
  the depot reads fuller than it is.
- **Whether purchased BAR crates actually arrive stocked.** `barempty` zeroes
  `BuildAndRessources_ressources` on purchase on the assumption that BAR spawns
  its crates carrying material. If BAR already spawns them empty this is a
  harmless no-op; if BAR sets the contents *after* `fn_initObject` runs, the
  zeroing is defeated and the flag needs moving to a later hook.
- **The global-settings change.** `A3A_CHAOS_influenceRange` and
  `A3A_CHAOS_influenceReach` moved from `isGlobal 0` to `isGlobal 2`. Existing
  servers will fall back to the default (800 m / 2.0) unless the value is set in
  the server's CBA settings file — a per-client value from before is no longer
  honoured. Worth calling out in release notes.

## Open design questions, deliberately not decided

- **Enemy supply visibility.** The server does not publish enemy edges, because
  handing every client a live map of the enemy network with no scouting is a
  decision nobody has made. The data exists server-side; wiring an intel
  mechanism (captured laptop, interrogation) is a self-contained follow-up.
- **Depots as a failure surface.** Depot destruction currently severs nothing:
  `fn_chooseAttack` picks *markers*, so a depot is only ever attacked
  incidentally. The corridor-severance mechanic is what actually cuts lines.
  Making depot raids matter needs a mission type added to the attack director.
- **Per-marker tiers.** Not implemented. Tier 1 (the depot run), tier 2
  (mechanisation / labour), tier 3 (processing / retooling) all imply new saved
  state per marker and a renormalisation decision — see below.

## Traps for whoever picks this up

1. **The economy is normalised per map.** `fn_initZones` sets
   `A3A_rebelCashResMult = 1500 / count resourcesX` and
   `A3A_rebelCashFactMult = 1.4 / count factories`, so all resources on any map
   are collectively worth 1500/tick and all factories +140%. Tier multipliers
   compound with each other (resources are additive, factories multiplicative),
   so a fully tiered map is not 3x income, it is closer to 3 x 3. Any tier
   ladder needs an explicit ceiling and an explicit inflation target.
2. **Dynamically added resource markers inflate.** Those multipliers are
   computed once at init, so a marker added mid-campaign is worth a full share
   rather than diluting the pot. Worse, `fn_tierCheck` derives `_totalPoints`
   from `count resourcesX`, so adding one can retroactively *demote* the war
   tier. Surveyed sites should live in a separate list excluded from
   `tierCheck`.
3. **The draw-order swap in `fn_computeInfluenceZones` reorders sides.** It now
   operates on shallow copies, because the context's spatial index stores side
   *indices* into the order the context built. If you ever reorder a context's
   arrays in place, that index is silently wrong.
4. **`fn_influenceAt` duplicates the rasteriser's cone and saturation maths** —
   deliberately, because a function call per grid node would cost the overlay
   far more than the duplication costs us. Every *constant* is shared via the
   context, so only four lines are duplicated. Change one, change the other:
   sections 5 and 6 of `fn_computeInfluenceZones` are the counterparts.
5. **Log macros split on every comma.** An array literal inline in a `Debug_N`
   drops the macro and fails the *whole file* to compile. Build the array into a
   local first. `Tools/sqfcheck` cannot catch this.

## Suggested next steps, in order

1. Play a campaign to the point of owning a factory and a depot, and read
   `A3A_supplyGraphMs` and the `computeSupplyGraph` debug lines out of the RPT.
   Everything else is guesswork until that number exists.
2. Tune `A3A_CHAOS_barFactoryYield` against how much material a real base build
   consumes. 200/factory/tick is a placeholder, not a balanced number.
3. Decide the enemy-intel question, then publish enemy edges behind it.
4. Only then start on per-marker tiers, with the renormalisation decision made
   first and the save functions extended in the same change.
