<#
.SYNOPSIS
    Self-test for sqfcheck: every fixture under tests/ must produce exactly the codes declared on
    its first line, and both engines (PowerShell and Python) must agree on every fixture.

.DESCRIPTION
    Fixture naming: each tests/*.sqf carries an "// expect: E001,W001" comment on its first line
    (an empty list means the file must be reported clean).

    The Python engine is only exercised when an interpreter is available; when it is, its findings
    are compared code-for-code against the PowerShell engine so the two implementations cannot
    drift apart unnoticed.

.NOTES
    Exit code 0 = all assertions passed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot 'Check-Sqf.ps1'
$pyEngine = Join-Path $PSScriptRoot 'sqfcheck.py'
$testDir = Join-Path $PSScriptRoot 'tests'
$noBaseline = Join-Path $testDir 'no-baseline'
$failures = 0

function Get-PythonCommand {
    foreach ($candidate in 'py', 'python3', 'python') {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        try {
            $null = & $candidate -c 'import sys' 2>&1
            if ($LASTEXITCODE -eq 0) { return $candidate }
        } catch { }
    }
    return $null
}

$python = Get-PythonCommand
if ($python) {
    Write-Host ("Python engine: {0}" -f $python) -ForegroundColor Cyan
} else {
    Write-Host 'Python engine: not available - testing the PowerShell engine only.' -ForegroundColor Yellow
}

function Get-Codes([string] $json) {
    if (-not $json) { return @() }
    return @(($json | ConvertFrom-Json) | ForEach-Object { $_.Code } | Sort-Object -Unique)
}

foreach ($file in (Get-ChildItem -LiteralPath $testDir -Filter *.sqf | Sort-Object Name)) {
    $expected = @()
    $first = (Get-Content -LiteralPath $file.FullName -TotalCount 1)
    if ($first -match '^//\s*expect:\s*(.+)$') {
        $expected = @($Matches[1] -split '[,\s]+' | Where-Object { $_ })
    }

    $psCodes = Get-Codes (& pwsh -NoProfile -File $checker -Engine powershell `
        -Baseline $noBaseline -Json -Strict $file.FullName | Out-String)

    $missing = @($expected | Where-Object { $_ -notin $psCodes })
    $extra = @($psCodes | Where-Object { $_ -notin $expected })

    $pyCodes = $null
    $mismatch = @()
    if ($python) {
        $pyCodes = Get-Codes (& $python $pyEngine --baseline $noBaseline --json --strict $file.FullName | Out-String)
        $mismatch = @(@($psCodes | Where-Object { $_ -notin $pyCodes }) +
                      @($pyCodes | Where-Object { $_ -notin $psCodes }))
    }

    if ($missing.Count -or $extra.Count -or $mismatch.Count) {
        $failures++
        Write-Host ("FAIL {0}" -f $file.Name) -ForegroundColor Red
        if ($missing) { Write-Host ("     expected but not reported: {0}" -f ($missing -join ', ')) }
        if ($extra) { Write-Host ("     reported but not expected:  {0}" -f ($extra -join ', ')) }
        if ($mismatch) {
            Write-Host ("     engines disagree - powershell: [{0}]  python: [{1}]" -f `
                ($psCodes -join ','), ($pyCodes -join ',')) -ForegroundColor Magenta
        }
    } else {
        $suffix = if ($python) { ' (both engines)' } else { '' }
        Write-Host ("ok   {0} [{1}]{2}" -f $file.Name, ($expected -join ','), $suffix) -ForegroundColor Green
    }
}

# The fixtures are deliberately broken, so a directory scan that reaches them would fail CI on
# every push touching Tools/sqfcheck. Both engines must skip them unless named explicitly.
foreach ($engine in @('powershell', 'python')) {
    if ($engine -eq 'python' -and -not $python) { continue }

    $scan = if ($engine -eq 'powershell') {
        & pwsh -NoProfile -File $checker -Engine powershell -Baseline $noBaseline -Json -Strict $PSScriptRoot | Out-String
    } else {
        & $python $pyEngine --baseline $noBaseline --json --strict $PSScriptRoot | Out-String
    }

    $leaked = @(Get-Codes $scan)
    if ($leaked.Count) {
        $failures++
        Write-Host ("FAIL fixture-exclusion ({0})" -f $engine) -ForegroundColor Red
        Write-Host ("     scanning Tools/sqfcheck reported [{0}] - tests/ fixtures are not excluded" -f ($leaked -join ','))
    } else {
        Write-Host ("ok   fixture-exclusion ({0})" -f $engine) -ForegroundColor Green
    }
}

if ($failures -gt 0) {
    Write-Host ("{0} check(s) failed" -f $failures) -ForegroundColor Red
    exit 1
}
Write-Host 'sqfcheck self-test passed.' -ForegroundColor Green
exit 0
