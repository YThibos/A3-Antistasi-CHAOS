<#
.SYNOPSIS
    Claude Code PostToolUse hook: syntax-check an SQF file right after it is written or edited.

.DESCRIPTION
    Reads the hook payload (JSON) from stdin, takes the edited file path, and runs
    Check-Sqf.ps1 on it when it is a .sqf file.

    Exit codes follow the Claude Code hook contract:
      0  nothing to say
      2  blocking feedback - stderr is fed back to the agent so it fixes the file immediately

    Wired up in .claude/settings.json; also usable standalone:
      echo '{"tool_input":{"file_path":"A3A/.../fn_x.sqf"}}' | pwsh -File Tools/sqfcheck/Invoke-EditHook.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json
} catch {
    exit 0   # never block on a payload we cannot parse
}

$paths = @()
foreach ($candidate in @('file_path', 'filePath', 'path', 'notebook_path')) {
    if ($payload.PSObject.Properties.Name -contains 'tool_input' -and
        $payload.tool_input.PSObject.Properties.Name -contains $candidate) {
        $paths += $payload.tool_input.$candidate
    }
}
# MultiEdit / batch edits
if ($payload.PSObject.Properties.Name -contains 'tool_input' -and
    $payload.tool_input.PSObject.Properties.Name -contains 'edits') {
    foreach ($e in $payload.tool_input.edits) {
        if ($e.PSObject.Properties.Name -contains 'file_path') { $paths += $e.file_path }
    }
}

$sqf = @($paths | Where-Object { $_ -and $_.EndsWith('.sqf', [System.StringComparison]::OrdinalIgnoreCase) } |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
if ($sqf.Count -eq 0) { exit 0 }

$checker = Join-Path $PSScriptRoot 'Check-Sqf.ps1'
$output = & pwsh -NoProfile -File $checker @sqf 2>&1
$code = $LASTEXITCODE

if ($code -eq 1) {
    [Console]::Error.WriteLine("sqfcheck found syntax errors in the file you just wrote. Fix them now, then re-run:")
    [Console]::Error.WriteLine(($output | Out-String))
    exit 2
}

# Warnings only: surface them without blocking.
if ($output -match ': warn ') {
    [Console]::Error.WriteLine(($output | Out-String))
}
exit 0
