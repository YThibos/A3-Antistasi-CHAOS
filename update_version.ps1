# Update Version Script
# Syncs version from dev_version.txt into script_version.hpp
# Run this whenever you bump the version, then commit both files.
# Usage: .\update_version.ps1

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Antistasi CHAOS - Version Update" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

$versionFile       = "dev_version.txt"
$scriptVersionFile = "A3A\addons\core\Includes\script_version.hpp"

if (!(Test-Path $versionFile))
{
    Write-Host "ERROR: $versionFile not found!" -ForegroundColor Red
    Write-Host "Create it with a single line in the format MAJOR.MINOR.PATCH (e.g. 3.11.1)" -ForegroundColor Yellow
    exit 1
}

$version = (Get-Content $versionFile -First 1).Trim()
Write-Host "Version from $versionFile`: $version" -ForegroundColor White

if ($version -match '^(\d+)\.(\d+)\.(\d+)$')
{
    $major = $Matches[1]
    $minor = $Matches[2]
    $patch = $Matches[3]
    Write-Host "Parsed: MAJOR=$major  MINOR=$minor  PATCHLVL=$patch" -ForegroundColor White
}
else
{
    Write-Host "ERROR: Invalid version format in $versionFile" -ForegroundColor Red
    Write-Host "Expected format: MAJOR.MINOR.PATCH (e.g. 3.11.1)" -ForegroundColor Yellow
    exit 1
}

if (!(Test-Path $scriptVersionFile))
{
    Write-Host "ERROR: $scriptVersionFile not found!" -ForegroundColor Red
    exit 1
}

$newContent = foreach ($line in (Get-Content $scriptVersionFile))
{
    switch -Regex ($line)
    {
        '^#define MAJOR '    { "#define MAJOR $major" }
        '^#define MINOR '    { "#define MINOR $minor" }
        '^#define PATCHLVL ' { "#define PATCHLVL $patch" }
        '^#define BUILD '    { "#define BUILD 0" }
        default              { $line }
    }
}

Set-Content -Path $scriptVersionFile -Value $newContent

Write-Host ""
Write-Host "=======================================" -ForegroundColor Green
Write-Host "VERSION UPDATE COMPLETE!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host "Version: $version  (MAJOR=$major, MINOR=$minor, PATCHLVL=$patch, BUILD=0)" -ForegroundColor White
Write-Host "Updated: $scriptVersionFile" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Build:   .\build_dev.ps1" -ForegroundColor White
Write-Host "2. Commit the version bump (both files)" -ForegroundColor White
Write-Host ""

