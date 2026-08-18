# Manual Deployment Script for Antistasi CHAOS
# Use this when the auto-deploy inside build_dev.ps1 fails (e.g. permission issues,
# Arma 3 process lock) or when you want a confirmed interactive deploy.
# Usage: .\deploy_manual.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "MANUAL DEPLOYMENT - Antistasi CHAOS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$SOURCE = "C:\dev\sources\arma3\A3-Antistasi-CHAOS\build\@Antistasi-CHAOS"
$TARGET = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3\@Antistasi-CHAOS"

# Bail out if Arma 3 is running
Write-Host "Checking if Arma 3 is running..." -ForegroundColor Yellow
$arma3Process = Get-Process -Name "arma3_x64" -ErrorAction SilentlyContinue
if ($arma3Process)
{
    Write-Host "ERROR: Arma 3 is running! Please close it first." -ForegroundColor Red
    Write-Host "Found process ID: $($arma3Process.Id)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "[OK] Arma 3 is not running" -ForegroundColor Green
Write-Host ""

# Check source exists
if (-not (Test-Path $SOURCE))
{
    Write-Host "ERROR: Source build not found!" -ForegroundColor Red
    Write-Host "Path: $SOURCE" -ForegroundColor Red
    Write-Host "Please run build_dev.ps1 first." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Source: $SOURCE" -ForegroundColor White
Write-Host "Target: $TARGET" -ForegroundColor White
Write-Host ""
Write-Host "WARNING: This will delete the old mod and replace it with the new build." -ForegroundColor Yellow
$confirm = Read-Host "Continue? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y")
{
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Removing old mod directory..." -ForegroundColor Yellow
if (Test-Path $TARGET)
{
    try
    {
        Remove-Item $TARGET -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Old mod removed" -ForegroundColor Green
    }
    catch
    {
        Write-Host "ERROR: Could not remove old directory!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Make sure Arma 3 is completely closed and you have admin rights." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}
else
{
    Write-Host "[OK] No old mod to remove" -ForegroundColor Green
}

Write-Host "Copying new mod..." -ForegroundColor Yellow
try
{
    New-Item -Path $TARGET -ItemType Directory -Force | Out-Null
    Copy-Item -Path "$SOURCE\*" -Destination $TARGET -Recurse -Force -ErrorAction Stop
    Write-Host "[OK] Mod copied successfully" -ForegroundColor Green
}
catch
{
    Write-Host "ERROR: Copy failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Show deployed PBOs and timestamps
$pbos = Get-ChildItem "$TARGET\addons\*.pbo" -ErrorAction SilentlyContinue
if ($pbos)
{
    Write-Host "Deployed PBOs:" -ForegroundColor Cyan
    $pbos | Select-Object Name, LastWriteTime | Format-Table -AutoSize
}

Write-Host "You can now start Arma 3 and test the mod." -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"

