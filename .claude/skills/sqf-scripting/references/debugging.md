# Debugging SQF

## Before the game

1. `pwsh -NoProfile -File Tools/sqfcheck/Check-Sqf.ps1 -Changed` — catches the structural errors.
2. Re-read the function header: does the caller match the `params` contract?
3. Ask *where* it runs (server / client / owner) before asking *why* it fails.

## In the game

- Launch with `-showScriptErrors` (and `-debug -filePatching` for a dev build) so errors appear
  on screen instead of only in the log.
- The log: `%LOCALAPPDATA%\Arma 3\arma3_x64.rpt` (client) and the server's `.rpt` next to the
  server executable. `#line` fixes from `FIX_LINE_NUMBERS()` make the reported file/line real.
- Debug console (Esc in the editor, or admin in MP): the *Exec* field runs in the **scheduled**
  environment, so code that works there may still fail inside an event handler.
- Useful diagnostics: `diag_log`, `diag_fps`, `diag_activeSQFScripts`, `diag_activeMissionFSMs`,
  `diag_frameNo`, `diag_tickTime`, `systemChat str _x`, `copyToClipboard str _x`,
  `BIS_fnc_arrayShow`, `BIS_fnc_error`.

## Reading a .rpt error

```
Error in expression <_units select _i>
  Error Zero divisor / Undefined variable in expression: _units
File x\A3A\addons\core\functions\Base\fn_doThing.sqf..., line 42
```

- *Undefined variable* → dynamic scoping: the variable was never set on this machine, was set in a
  sibling scope, or the code ran in an isolated scope (`spawn`, event handler, `remoteExec`).
- *Type Any expected …* → a `params` contract was violated by the caller, or a command returned
  `nil` (usually `getVariable` without a default, or an out-of-range `select`).
- *Generic error in expression* → often a null object or a missing config path.
- An error with **no file/line** usually comes from `compile`d string code or a missing
  `FIX_LINE_NUMBERS()` after an `#include`.

## Antistasi logging

Use the log macros from `A3A/addons/core/Includes/LogMacros.inc` rather than raw `diag_log`:

```sqf
Info_1("spawnGarrison: %1 units queued", _n);
Debug_2("marker %1 at %2", _marker, _pos);
Error_1("bad side %1", _side);
ServerInfo_1("…", _x);     // force the message onto the server log
```

They respect the `LogLevel` setting, tag the source, and compile out entirely when disabled — so
they are safe to leave in shipped code, unlike `diag_log`/`hint`.

## Reproducing multiplayer bugs

- Host a local server and join with a second client; a hosted host hides server/client bugs
  because everything is local. A dedicated local server reproduces properly.
- Check whether the bug follows the *object owner* or the *machine* — that distinction usually
  names the bug.
- For save/persistence bugs, save, reload, and diff the state you expected against
  `profileNamespace`/save data — new state usually just was never added to the save code.
