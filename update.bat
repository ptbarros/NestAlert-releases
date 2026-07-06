@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  NestAlert device updater (Windows).
REM  Double-click to run. Downloads the latest firmware and flashes it
REM  to a device over USB. Nothing to pre-install (Windows 10/11 ship
REM  curl + PowerShell). Flashing does NOT erase device config (WiFi /
REM  token / name) or the nest cache.
REM ===================================================================

set "REPO=ptbarros/NestAlert-releases"
set "BASE=https://github.com/%REPO%/releases/latest/download"
set "ESPVER=v5.0.0"
set "HERE=%~dp0"
set "WORK=%HERE%.cache"
if not exist "%WORK%" mkdir "%WORK%"

echo ===================================================
echo    NestAlert device updater
echo ===================================================

REM --- 1. esptool standalone (download once) ---------------------------------
set "ESPDIR=%WORK%\esptool-%ESPVER%-windows-amd64"
set "ESPTOOL=%ESPDIR%\esptool.exe"
if not exist "%ESPTOOL%" (
  echo ^>^> downloading esptool %ESPVER% ^(one time^) ...
  curl -fL "https://github.com/espressif/esptool/releases/download/%ESPVER%/esptool-%ESPVER%-windows-amd64.zip" -o "%WORK%\esptool.zip"
  if errorlevel 1 ( echo Could not download esptool. Check the internet connection. & pause & exit /b 1 )
  powershell -NoProfile -Command "Expand-Archive -Force '%WORK%\esptool.zip' '%WORK%'"
)

REM --- 2. fetch the latest firmware + checksums ------------------------------
echo ^>^> fetching latest firmware ...
for %%f in (manifest.json SHA256SUMS bootloader.bin partitions.bin boot_app0.bin app.bin) do (
  curl -fL "%BASE%/%%f" -o "%WORK%\%%f"
  if errorlevel 1 ( echo Download failed ^(%%f^). Check the internet connection. & pause & exit /b 1 )
)
for /f "usebackq tokens=2 delims=:," %%v in (`findstr /C:"\"version\"" "%WORK%\manifest.json"`) do (
  set "VERSION=%%~v"
)
set "VERSION=%VERSION: =%"
set "VERSION=%VERSION:"=%"
echo ^>^> firmware version: %VERSION%

REM --- 3. verify the downloads (PowerShell hashes vs SHA256SUMS) -------------
powershell -NoProfile -Command ^
  "$ok=$true; Get-Content '%WORK%\SHA256SUMS' | ForEach-Object { $p=$_ -split '\s+',2; $h=$p[0]; $f=$p[1].Trim('* '); $a=(Get-FileHash (Join-Path '%WORK%' $f) -Algorithm SHA256).Hash; if($a -ne $h.ToUpper()){ Write-Host ('MISMATCH ' + $f); $ok=$false } }; if(-not $ok){ exit 1 }"
if errorlevel 1 ( echo CHECKSUM MISMATCH - download looks corrupted. Re-run to try again. & pause & exit /b 1 )
echo ^>^> checksums OK

REM --- 4. flash loop (one device at a time) ---------------------------------
REM esptool auto-detects the COM port when --port is omitted.
:loop
echo.
set "ans="
set /p "ans=Plug in ONE device, then press ENTER to flash it (or type q then ENTER to quit): "
if /I "!ans!"=="q" goto end
echo ^>^> flashing %VERSION% ...
"%ESPTOOL%" --chip esp32s3 --baud 921600 write-flash 0x0 "%WORK%\bootloader.bin" 0x8000 "%WORK%\partitions.bin" 0xe000 "%WORK%\boot_app0.bin" 0x10000 "%WORK%\app.bin"
if errorlevel 1 (
  echo.
  echo    [X] FLASH FAILED - try a different USB cable/port, then retry.
) else (
  echo.
  echo    [OK] SUCCESS - flashed %VERSION%.
  echo         Confirm: the device's PMU screen should show Ver: %VERSION%
)
goto loop
:end
echo Done.
pause
