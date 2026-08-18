# Quick development build script for Antistasi CHAOS
# Builds, then auto-deploys to the local Arma 3 directory for testing.
# Usage: .\build_dev.ps1

param(
    [string]$modFileName = "mod_dev.cpp",
    [string]$outputPath = "@Antistasi-CHAOS",
    [switch]$Help
)

if ($Help)
{
    Write-Host @"
Antistasi CHAOS - Dev Build Script
====================================

Usage: .\build_dev.ps1 [OPTIONS]

Options:
    -modFileName <file>    Specify which mod file to use (default: mod_dev.cpp)
    -outputPath <name>     Output folder name (default: @Antistasi-CHAOS)
    -Help                  Show this help message

Examples:
    .\build_dev.ps1                                 # Build to build\@Antistasi-CHAOS\
    .\build_dev.ps1 -modFileName mod.cpp            # Build with mod.cpp
    .\build_dev.ps1 -outputPath "@A3A-CHAOS"        # Build to build\@A3A-CHAOS\

Output: build\`$outputPath\
"@
    exit 0
}

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Antistasi CHAOS - Dev Build" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date

Write-Host "Starting build process..." -ForegroundColor Yellow
Write-Host "Output directory: build\$outputPath\" -ForegroundColor Cyan
& ".\Tools\Builder\buildAddons.ps1" -modFileName $modFileName -customOutputPath $outputPath

if ($LASTEXITCODE -eq 0 -or $?)
{
    $endTime = Get-Date
    $duration = $endTime - $startTime

    # Read version from dev_version.txt and append -dev suffix
    $version = "unknown"
    if (Test-Path "dev_version.txt")
    {
        $version = (Get-Content "dev_version.txt" -First 1).Trim()
        $version = "$version-dev"
    }

    # Create version string for filename (e.g. 3.11.1-dev -> v3-11-1-dev)
    $versionForFilename = "v" + ($version -replace '\.', '-')

    # Drop a timestamp file in the build folder for easy identification
    $timestamp = Get-Date -Format "yyyyMMdd-HHmm"
    $timestampFilename = "$versionForFilename-$timestamp.txt"
    $timestampFile = "build\$outputPath\$timestampFilename"
    Set-Content -Path $timestampFile -Value "Build: $timestamp`nVersion: $version"

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "Version:          $version" -ForegroundColor White
    Write-Host "Output Location:  build\$outputPath\" -ForegroundColor White
    Write-Host "Build Time:       $($duration.ToString('mm\:ss'))" -ForegroundColor White
    Write-Host "Build Timestamp:  $timestampFilename" -ForegroundColor White
    Write-Host ""

    # ── Deploy to Arma 3 ─────────────────────────────────────────────────────
    Write-Host "Deploying to Arma 3..." -ForegroundColor Yellow
    $arma3ModPath = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3\$outputPath"

    try
    {
        # Ensure the Arma 3 directory itself exists (handles non-default installs)
        $arma3ParentPath = Split-Path $arma3ModPath -Parent
        if (!(Test-Path $arma3ParentPath))
        {
            New-Item -Path $arma3ParentPath -ItemType Directory -Force | Out-Null
        }

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
        Write-Host "Mod deployed to: $arma3ModPath" -ForegroundColor White
        Write-Host ""

        # ── Sanity-check: core.pbo ────────────────────────────────────────────
        Write-Host "Verifying core addon deployment..." -ForegroundColor Yellow
        $corePboPath      = "$arma3ModPath\addons\core.pbo"
        $buildCorePboPath = "build\$outputPath\addons\core.pbo"

        if (Test-Path $corePboPath)
        {
            $deployedFile = Get-Item $corePboPath
            $buildFile    = Get-Item $buildCorePboPath

            if ($deployedFile.Length -eq $buildFile.Length)
            {
                Write-Host "[OK] core.pbo deployed successfully" -ForegroundColor Green
                Write-Host "     Size:     $($deployedFile.Length) bytes" -ForegroundColor Gray
                Write-Host "     Modified: $($deployedFile.LastWriteTime)" -ForegroundColor Gray
            }
            else
            {
                Write-Host "[WARNING] core.pbo size mismatch!" -ForegroundColor Yellow
                Write-Host "          Build:    $($buildFile.Length) bytes" -ForegroundColor Gray
                Write-Host "          Deployed: $($deployedFile.Length) bytes" -ForegroundColor Gray
            }
        }
        else
        {
            Write-Host "[ERROR] core.pbo NOT FOUND in deployed folder!" -ForegroundColor Red
            Write-Host "        Expected at: $corePboPath" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Launch Arma 3 Launcher and enable the mod (if not already enabled)" -ForegroundColor White
        Write-Host "2. Start the game and test your changes" -ForegroundColor White
        Write-Host "3. Build info: build\$outputPath\$timestampFilename" -ForegroundColor White
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
        Write-Host "1. Copy 'build\$outputPath' to '$arma3ModPath'" -ForegroundColor White
        Write-Host "2. Launch Arma 3 Launcher and enable the mod" -ForegroundColor White
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

