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
REM  The v5.0.0 zip unpacks to a folder WITHOUT the version in its name
REM  ("esptool-windows-amd64"), so locate esptool.exe by searching the cache
REM  rather than assuming a fixed path.
set "ESPTOOL="
for /r "%WORK%" %%e in (esptool.exe) do set "ESPTOOL=%%e"
if not defined ESPTOOL (
  echo ^>^> downloading esptool %ESPVER% ^(one time^) ...
  curl -fL "https://github.com/espressif/esptool/releases/download/%ESPVER%/esptool-%ESPVER%-windows-amd64.zip" -o "%WORK%\esptool.zip"
  if errorlevel 1 ( echo Could not download esptool. Check the internet connection. & pause & exit /b 1 )
  powershell -NoProfile -Command "Expand-Archive -Force '%WORK%\esptool.zip' '%WORK%'"
  for /r "%WORK%" %%e in (esptool.exe) do set "ESPTOOL=%%e"
)
if not defined ESPTOOL ( echo Could not locate esptool.exe after extracting. & pause & exit /b 1 )

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
:loop
echo.
set "ans="
set /p "ans=Plug in ONE device, then press ENTER to flash it (or type q then ENTER to quit): "
if /I "!ans!"=="q" goto end

REM Find the ESP32-S3's own COM port by its Espressif USB id (VID_303A), so a
REM second serial gadget (mouse dongle, etc.) on another COM is ignored.
set "PORT="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "Get-PnpDevice -Class Ports -PresentOnly -ErrorAction SilentlyContinue ^| Where-Object { $_.InstanceId -match 'VID_303A' } ^| ForEach-Object { if($_.FriendlyName -match 'COM\d+'){$Matches[0]} }"`) do set "PORT=%%p"
if not defined PORT (
  echo.
  echo    [!] Could not find the NestAlert device's COM port.
  echo        Check Device Manager - it should appear under "Ports ^(COM ^& LPT^)"
  echo        as "USB Serial Device ^(COMx^)" when plugged in.
  echo        If it won't connect, force download mode: unplug, HOLD the BOOT button,
  echo        plug USB back in while holding, release BOOT ^(screen stays dark^), press ENTER.
  goto loop
)
echo ^>^> flashing %VERSION% to %PORT% ...
"%ESPTOOL%" --chip esp32s3 --port %PORT% --baud 921600 write-flash 0x0 "%WORK%\bootloader.bin" 0x8000 "%WORK%\partitions.bin" 0xe000 "%WORK%\boot_app0.bin" 0x10000 "%WORK%\app.bin"
if errorlevel 1 (
  echo.
  echo    [X] FLASH FAILED on %PORT%.
  echo        Force download mode and retry: unplug the device, HOLD the BOOT button,
  echo        plug USB back in while holding, release BOOT ^(screen stays dark^), press ENTER.
) else (
  echo.
  echo    [OK] SUCCESS - flashed %VERSION%.
  echo         Confirm: the device's PMU screen should show Ver: %VERSION%
)
goto loop
:end
echo Done.
pause
