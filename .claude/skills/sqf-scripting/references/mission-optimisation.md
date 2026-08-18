# Mission and runtime optimisation

Code optimisation makes a function faster; mission optimisation decides whether a 60-player
Antistasi campaign is playable at hour three. This is where the wins actually are.

## Where the frames go

| Cost | What to do about it |
|---|---|
| **AI unit count** | The dominant cost, on CPU *and* network. Use agents (`createAgent`) for civilians and anything that does not need full unit fidelity; use Dynamic Simulation to freeze distant AI; offload groups to headless clients; cap group sizes. |
| **Object count** | Fewer objects = more FPS. Simple objects for decoration, garbage-collect bodies and wrecks, watch attachments/headgear/NVGs — each proxy costs. |
| **View distance** | Costs both CPU and GPU. Client-side setting; lowering it on clients reduces their position-update traffic too. |
| **Script count** | Too many concurrent scripts causes delays and stalls. Check with `diag_activeSQFScripts` / `diag_activeMissionFSMs`. |
| **Network messages** | Public variables, global-effect commands and unit creation all replicate. Batch and rate-limit them. |

## The patterns that matter

**One script over a list, not one script per unit.**

```sqf
{ _x spawn _myCode } forEach _units;    // bad: N scheduled scripts competing
_units call _myCode;                    // good: one pass, add/remove units from the list
```

**Never re-read files at runtime.** `execVM "file.sqf"` in a loop re-reads and recompiles every
time. Precompile once (`PREP` / `compile preprocessFileLineNumbers`) and `call` the function.

**Do not poll faster than the answer changes.**

```sqf
while {true} do { … };                       // bad
while {alive player} do { …; sleep 1 };      // acceptable in a scheduled script
[{ … }, 1] call CBA_fnc_addPerFrameHandler;  // better: predictable, unscheduled
```

Ask whether the check must be frame-perfect or can tolerate seconds. Most can.
Triggers default to a 0.5 s condition check — `setTriggerInterval` them up, keep the condition
cheap, and make them server-side where possible.

**Keep heavy work out of unscheduled code.** Unscheduled code is not throttled at all: a cyclic
expensive unscheduled block can freeze the game. Time-critical work goes unscheduled; anything
long-running should hand off (`CBA_fnc_waitAndExecute`, PFH batching, or a `spawn` if you truly
need suspension).

**Network hygiene**

- `publicVariable` / public `setVariable` are not per-frame tools; also, the *variable name length*
  is on the wire, so keep names sane.
- Global-effect commands replicate every call: prefer `attachTo` over repeated `setPos`, and update
  markers with the `…Local` commands, ending with one global call to sync the final state.
- Create units and vehicles in bursts at defined points, not continuously.
- Mission-critical calculation belongs on the server; local effects belong on the client.

## Diagnosing

```sqf
diag_fps, diag_fpsMin, diag_frameNo, diag_tickTime
diag_activeSQFScripts, diag_activeScripts, diag_activeMissionFSMs
count allUnits, count allGroups, count vehicles          // the usual suspects
```

Server console: `#monitor 5` (and `#monitords 5` on a dedicated server) prints server FPS and
condition/AI load; `0` stops it. Compare against a vanilla run of the same terrain to separate mod
cost from engine cost, and single-player against multiplayer to separate compute from network.
