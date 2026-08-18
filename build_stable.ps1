# Stable build script for Antistasi CHAOS
# Builds the release version and deploys it locally for a final smoke-test
# before any Workshop upload.
# Usage: .\build_stable.ps1

param(
    [string]$outputPath = "@Antistasi-CHAOS",
    [switch]$Help
)

if ($Help)
{
    Write-Host @"
Antistasi CHAOS - Stable Build Script
=======================================

Usage: .\build_stable.ps1 [OPTIONS]

Options:
    -outputPath <name>     Output folder name (default: @Antistasi-CHAOS)
    -Help                  Show this help message

Examples:
    .\build_stable.ps1                            # Build stable release
    .\build_stable.ps1 -outputPath "@A3A-CHAOS"   # Custom output name

Output: build\`$outputPath\
"@
    exit 0
}

Write-Host "=======================================" -ForegroundColor Green
Write-Host "Antistasi CHAOS - Stable Build" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host ""

$startTime = Get-Date

Write-Host "Starting stable build process..." -ForegroundColor Yellow
Write-Host "Output directory: build\$outputPath\" -ForegroundColor Cyan
& ".\Tools\Builder\buildAddons.ps1" -modFileName "mod.cpp" -customOutputPath $outputPath

if ($LASTEXITCODE -eq 0 -or $?)
{
    $endTime = Get-Date
    $duration = $endTime - $startTime

    # Read version from dev_version.txt (no -dev suffix for stable)
    $version = "unknown"
    if (Test-Path "dev_version.txt")
    {
        $version = (Get-Content "dev_version.txt" -First 1).Trim()
    }

    # Create version string for filename (e.g. 3.11.1 -> v3-11-1)
    $versionForFilename = "v" + ($version -replace '\.', '-')

    # Drop a timestamp file in the build folder for identification
    $timestamp = Get-Date -Format "yyyyMMdd-HHmm"
    $timestampFilename = "$versionForFilename-$timestamp.txt"
    $timestampFile = "build\$outputPath\$timestampFilename"
    Set-Content -Path $timestampFile -Value "Stable Build: $timestamp`nVersion: $version"

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "STABLE BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "Version:         $version (STABLE)" -ForegroundColor White
    Write-Host "Output Location: build\$outputPath\" -ForegroundColor White
    Write-Host "Build Time:      $($duration.ToString('mm\:ss'))" -ForegroundColor White
    Write-Host "Build Timestamp: $timestampFilename" -ForegroundColor White
    Write-Host ""

    # ── Deploy to Arma 3 for local smoke-test ────────────────────────────────
    Write-Host "Deploying to Arma 3..." -ForegroundColor Yellow
    $arma3ModPath = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3\$outputPath"

    try
    {
        if (Test-Path $arma3ModPath)
        {
            Write-Host "Removing old mod directory..." -ForegroundColor White
            Remove-Item -Path $arma3ModPath -Recurse -Force -ErrorAction Stop
        }

        New-Item -Path $arma3ModPath -ItemType Directory -Force | Out-Null

        Write-Host "Copying new build to Arma 3 directory..." -ForegroundColor White
        Copy-Item -Path "build\$outputPath\*" -Destination $arma3ModPath -Recurse -Force -ErrorAction Stop

        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Green
        Write-Host "DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
        Write-Host "=======================================" -ForegroundColor Green
        Write-Host "Stable mod deployed to: $arma3ModPath" -ForegroundColor White
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Launch Arma 3 and smoke-test the stable build" -ForegroundColor White
        Write-Host "2. If everything checks out, the build\$outputPath\ folder is" -ForegroundColor White
        Write-Host "   ready for Workshop upload." -ForegroundColor White
        Write-Host ""
    }
    catch
    {
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Red
        Write-Host "DEPLOYMENT FAILED!" -ForegroundColor Red
        Write-Host "=======================================" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual deployment required:" -ForegroundColor Yellow
        Write-Host "Copy 'build\$outputPath' to '$arma3ModPath'" -ForegroundColor White
        Write-Host ""
    }
}
else
{
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    Write-Host "=======================================" -ForegroundColor Red
    Write-Host "Please check the error messages above." -ForegroundColor White
    Write-Host ""
    exit 1
}

