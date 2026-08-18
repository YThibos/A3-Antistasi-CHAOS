# Execution model: scheduled vs unscheduled

Arma runs SQF in two environments, and almost every "it works alone but not in a mission" bug
comes from confusing them.

## Unscheduled (non-scheduled) environment

- Runs **linearly to completion inside the current frame**. Nothing can interrupt it.
- Entered by: `call`, event handlers (`addEventHandler`, XEH, `addMissionEventHandler`),
  CBA per-frame handlers, `preInit`/`postInit` functions, `onEachFrame`, config-called code,
  Extended Event Handlers, `remoteExec` receivers, most UI handlers.
- `sleep`, `uiSleep` and `waitUntil` **throw an error** here (`waitUntil` is only legal if
  `canSuspend` is true). Long loops here freeze the whole game for that frame.

## Scheduled environment

- Entered by: `spawn`, `execVM`, `addAction` code, `execFSM`, the debug console's *Exec* in SP.
- The scheduler gives each script ~**3 ms per frame**, then suspends it and moves to the next
  script in a queue shared by *every mod on the machine*. Under load a script can stall for
  seconds — or, if the queue never drains, never finish.
- Roughly **7× slower** than unscheduled for the same code.
- Anything spawned from scheduled code stays scheduled; anything `call`ed inherits the caller's
  environment.

### The consequence that actually bites

Execution can be suspended **between any two statements**. Anything you read before a suspension
may be stale afterwards:

```sqf
if (alive _target) then {
    sleep 1;                       // _target may be dead, deleted, or remote now
    _target setDamage 0;           // acting on a stale assumption
};
```

Re-validate objects, group membership and mission state after every suspension point.

## House rules

1. **Default to `call`.** A function that does not wait must not be `spawn`ed.
2. **Never use `execVM`** in mod code — it reads and compiles the file on every call. Functions
   are precompiled at mission start (see the `antistasi-codebase` skill's `PREP` section).
3. **Replace waiting with scheduling:**

   | Instead of | Use |
   |---|---|
   | `sleep 5; …` | `[{ … }, _args, 5] call CBA_fnc_waitAndExecute;` |
   | `waitUntil {_c}; …` | `[{ _cond }, { … }, _args] call CBA_fnc_waitUntilAndExecute;` |
   | `while {true} do { …; sleep 1 }` | `[{ … }, 1, _args] call CBA_fnc_addPerFrameHandler;` |
   | polling a state each frame | an event: `CBA_fnc_addEventHandler` / `A3A` events |
   | `spawn` for a slow one-off loop | `CBA_fnc_execNextFrame`, or chunk it across PFH ticks |

4. **Event-driven beats polling.** If something must react to a change, raise an event where the
   change happens rather than watching for it.
5. **Do not busy-loop over thousands of objects in one frame.** Batch: process N per PFH tick.
6. Store the PFH handle and remove it (`CBA_fnc_removePerFrameHandler`) — an orphaned PFH runs for
   the rest of the mission.
7. `isNil`, `canSuspend`, `diag_frameNo`, `time`, `diag_tickTime` help you assert where you are:
   `if (canSuspend) then { … }` tells you you are in the scheduled environment.

## Initialisation order (mod-relevant subset)

`preInit` functions → object init lines / `initServer.sqf` / `initPlayerLocal.sqf` →
`postInit` functions → first frame → `CBA_fnc_waitUntilAndExecute` callbacks.

Never assume another component's globals exist during `preInit`; guard with `isNil` or move the
work to `postInit`, an event, or `CBA_fnc_waitUntilAndExecute`.
