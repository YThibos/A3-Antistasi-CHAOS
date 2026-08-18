# Multiplayer, locality and remoteExec

Antistasi is a multiplayer mission first. Code that ignores locality works perfectly in the editor
and breaks on a dedicated server.

## Where am I?

```sqf
isServer            // true on the server and in SP/hosted host
isDedicated         // true only on a headless dedicated server (no player)
hasInterface        // true on any machine with a screen (players, incl. hosted host)
isMultiplayer
local _object       // true where this object's simulation is owned
_object == player
isServer && !hasInterface   // dedicated server
```

An object is **local** to exactly one machine: the server for AI/empty vehicles, the owning client
for a player and their group's AI, or a headless client if offloaded. Ownership can change at
runtime (`setOwner`, player joining a group, HC transfer) — check `local` at the moment of use,
never cache it.

## Which commands need locality

- **Local-effect commands** must run where the object is local: `setDamage`, `setPos*`, `setDir`,
  `doMove`, `move`, `setBehaviour`, `setSpeedMode`, `addWeapon`, `setUnitPos`, `disableAI`,
  `setVelocity`, most AI and inventory commands.
- **Global-effect commands** replicate themselves and may run anywhere: `hideObjectGlobal`,
  `enableSimulationGlobal`, `allowDamage`'s global sibling `allowDamage` via
  `[_o,false] remoteExec ["allowDamage", _o]`, `setVariable [_,_,true]`, `createMarker`,
  `setMarkerPos`, `deleteVehicle` (run it on the server), `createVehicle` (creates on the calling
  machine, so create on the server).
- Watch the `…Local` / `…Global` command pairs: `setMarkerPos` vs `setMarkerPosLocal`,
  `hideObject` vs `hideObjectGlobal`, `enableSimulation` vs `enableSimulationGlobal`. The bare name
  is not reliably the global one — check before using.
- When unsure, check the command's wiki entry for the "Global/Local Effect" and "Local Arguments"
  icons and write the answer into the function header.

## remoteExec

```sqf
[_unit, "MIDDLE"] remoteExec ["setUnitPos", _unit];      // to the owner of _unit
[_text] remoteExec ["hint", _clientOwnerId];             // to one machine
["msg"] remoteExec ["systemChat", 0];                    // to everyone currently connected
[_obj, true] remoteExec ["hideObjectGlobal", 2];         // to the server
[_arr] remoteExec ["A3A_fnc_doThing", 0, true];          // everyone + JIP-persistent
[_arr] remoteExec ["A3A_fnc_doThing", 0, "myJipId"];     // replaceable JIP entry
remoteExec ["", "myJipId"];                              // remove that JIP entry
```

Targets: `0` = everyone, `2` = server, a negative id = everyone except that machine, an object =
its owner, an array = list of ids/objects, `remoteExecutedOwner` = the caller inside the callee.

Rules:

- Prefer `remoteExecCall` when the receiver's code does not suspend — it runs unscheduled and
  cheaper. `remoteExec` runs the target in the scheduled environment.
- **Never** `remoteExec` code blocks (`{ … }` as the function) in shipped code: it is slower,
  unfilterable by CfgRemoteExec, and a security hole. Call a named `A3A_fnc_*` function.
- Send the smallest payload. Every call is network traffic; a per-frame `remoteExec` is a bug.
- JIP-persistent calls (`true` or a string id) accumulate forever unless you remove them. Use a
  string id you can overwrite/remove.
- The receiving machine may not have the object yet, or it may be `objNull`. Validate on arrival.

## State replication

- `setVariable [name, value, true]` broadcasts and persists for JIP — the simplest correct way to
  share object state. It is not free: don't do it every frame, and don't put large arrays in it.
- `publicVariable`/`publicVariableServer` broadcast a global. Prefer namespaced `setVariable`.
- Markers: `createMarker` is global, `createMarkerLocal` is client-side only. Same for
  `setMarkerPos`/`setMarkerPosLocal`. Client-only UI markers should always use the `Local` variants.
- Group and unit creation must happen on the server (or the HC that will own it), then be
  configured before anything else touches it.

## JIP

A joining player runs `initPlayerLocal.sqf` with `didJIP == true`, gets JIP-queued `remoteExec`
calls, and *does not* get anything you broadcast before they joined. Anything a late joiner needs
must be in a JIP-persistent variable, a JIP `remoteExec` entry, or explicitly re-sent on the
`PlayerConnected`/`CBA_fnc_addPlayerEventHandler` events.

## Headless clients

Antistasi offloads AI groups to HCs. Do not assume `isServer` implies AI ownership — use
`local _unit` / `groupOwner _group`, and route local-effect commands with `remoteExec [_, _unit]`.
