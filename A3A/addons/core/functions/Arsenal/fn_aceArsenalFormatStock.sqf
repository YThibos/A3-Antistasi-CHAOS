#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()
/*
Maintainer: Antistasi CHAOS
    Formats a stock amount integer into a clean fixed-width indicator string.

Scope: Client
Environment: Unscheduled
Public: No

Params:
    0: NUMBER - Stock amount (-1 for unlimited, >= 0 for quantity)

Returns:
    STRING - Formatted prefix string, e.g. "[  ∞  ] " or "[ 012 ] "
*/
params [["_amount", 0, [0]]];

if (_amount == -1) exitWith { "[  ∞  ] " };

if (_amount > 999) then {
    private _kAmount = round (_amount / 1000);
    private _prefix = switch true do {
        case (_kAmount >= 100): { "" };
        case (_kAmount >= 10): { "0" };
        default { "00" };
    };
    format ["[ %1%2k ] ", _prefix, _kAmount]
} else {
    private _prefix = switch true do {
        case (_amount >= 100): { "" };
        case (_amount >= 10): { "0" };
        default { "00" };
    };
    format ["[ %1%2 ] ", _prefix, _amount]
};
