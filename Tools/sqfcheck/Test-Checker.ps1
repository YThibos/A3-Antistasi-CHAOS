<#
.SYNOPSIS
    Self-test for Check-Sqf.ps1: every fixture under tests/ must produce exactly the codes
    encoded in its file name, and good_*.sqf fixtures must be silent.

.NOTES
    Fixture naming: bad_<name>.sqf carries an "// expect: E001,W001" comment on its first line.
    Exit code 0 = all assertions passed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot 'Check-Sqf.ps1'
$testDir = Join-Path $PSScriptRoot 'tests'
$failures = 0

foreach ($file in (Get-ChildItem -LiteralPath $testDir -Filter *.sqf | Sort-Object Name)) {
    $expected = @()
    $first = (Get-Content -LiteralPath $file.FullName -TotalCount 1)
    if ($first -match '^//\s*expect:\s*(.+)$') {
        $expected = @($Matches[1] -split '[,\s]+' | Where-Object { $_ })
    }

    $json = & pwsh -NoProfile -File $checker -Baseline (Join-Path $testDir 'no-baseline') -Json -Strict $file.FullName
    $found = @()
    if ($json) { $found = @(($json | ConvertFrom-Json) | ForEach-Object { $_.Code } | Sort-Object -Unique) }

    $missing = @($expected | Where-Object { $_ -notin $found })
    $extra = @($found | Where-Object { $_ -notin $expected })

    if ($missing.Count -or $extra.Count) {
        $failures++
        Write-Host ("FAIL {0}" -f $file.Name) -ForegroundColor Red
        if ($missing) { Write-Host ("     expected but not reported: {0}" -f ($missing -join ', ')) }
        if ($extra) { Write-Host ("     reported but not expected:  {0}" -f ($extra -join ', ')) }
    } else {
        Write-Host ("ok   {0} [{1}]" -f $file.Name, ($expected -join ',')) -ForegroundColor Green
    }
}

if ($failures -gt 0) {
    Write-Host ("{0} fixture(s) failed" -f $failures) -ForegroundColor Red
    exit 1
}
Write-Host 'sqfcheck self-test passed.' -ForegroundColor Green
exit 0
