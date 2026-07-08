# Windows flashing — debugging handoff

Hand this to a Claude Code (or any assistant) running on the Windows PC that's
failing to flash a NestAlert device. It has everything needed to diagnose without
prior context.

---

## ✅ RESOLVED (2026-07-07) — verified flashing v7.3 to a real device on COM5

The `FLASH FAILED` symptom came from **three independent bugs in `update.bat`**, each
one masking the next. All are fixed and the script was verified end-to-end (fresh,
empty `.cache` → download → extract → detect port → flash → `SUCCESS`) on the field PC.

### Bug 1 — wrong esptool path (esptool never located)
- The esptool v5.0.0 zip unpacks to `esptool-windows-amd64\` (**no version** in the
  folder name), but the script looked for `esptool-v5.0.0-windows-amd64\esptool.exe`.
  That path never existed → a missing exe "ran" → instant error mislabeled as
  "FLASH FAILED → hold BOOT".
- **Also a follow-on trap:** searching with `for /r "%WORK%" %%e in (esptool.exe)` using
  a **literal** filename is wrong — `for /r` fabricates a path for *every* directory it
  walks **without checking existence**, so on an empty first-run cache `ESPTOOL` gets a
  bogus path, the download block is skipped, and a missing exe is flashed.
- **Fix:** search with a **wildcard** + exact-name guard, which only yields files that
  actually exist:
  ```bat
  for /r "%WORK%" %%e in (esptool*.exe) do if /I "%%~nxe"=="esptool.exe" set "ESPTOOL=%%e"
  ```

### Bug 2 — blank COM port passed to esptool ("No such command '921600'")
- Symptom: `>> flashing v7.3 to   ...` (blank port) then esptool prints
  **`No such command '921600'`**. With an empty `%PORT%`, the command became
  `esptool.exe --chip esp32s3 --port  --baud 921600 write-flash ...` — esptool consumed
  `--baud` as the port value and treated `921600` as a subcommand.
- Root cause: a `VID_303A` device can present a **second interface without a COM
  number**, so the old detection emitted a **whitespace line**. `for /f` sets `PORT` to
  the **last** line, so `PORT` became `" "`. And `if not defined PORT` only checks
  **existence**, not emptiness — so whitespace slipped past the guard.
- **Fix (two parts):**
  1. Detection now returns exactly one clean `COMx` token (first match only).
  2. Replaced `if not defined PORT` with a real validation:
     ```bat
     echo !PORT!| findstr /R /C:"^COM[0-9][0-9]*$" >nul
     if errorlevel 1 ( ...print "could not find device"... & goto loop )
     ```
     Blank / whitespace / garbage now loops back instead of launching a bad flash.

### Bug 3 — fragile `^|` pipe-escaping in the detection FOR /F
- The detection used caret-escaped pipes (`... ^| Where-Object ... ^| ForEach ...`)
  inside `for /f \`powershell ...\``. That escaping can misfire (PowerShell receives a
  literal `^`, errors, returns nothing) → `PORT` blank again.
- **Fix:** rewrote detection as **pipe-free** PowerShell (a `foreach` loop with `break`)
  so there are **no `|` characters at all**, hence no `^|` to break:
  ```bat
  for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "$found=''; foreach($d in (Get-PnpDevice -Class Ports -PresentOnly -ErrorAction SilentlyContinue)){ if($d.InstanceId -match 'VID_303A' -and $d.FriendlyName -match 'COM\d+'){ $found=$Matches[0]; break } }; Write-Output $found"`) do set "PORT=%%p"
  ```

### Added — "port is busy / Access is denied" hint on flash failure
- If esptool prints `Could not open COMx ... PermissionError(13, 'Access is denied.')`
  / *"port is busy"*, **another program is holding the port** — a Serial Monitor,
  Arduino IDE, PuTTY, or a **previous/parallel flash process that didn't exit**. The
  detected port is correct; it's just locked.
- A half-finished flash from an interrupted attempt can leave the device on a **black
  screen or boot-looping** (invalid app partition). This is **not a brick** — the
  ESP32-S3 ROM bootloader + native USB-JTAG live in mask ROM, so the device stays
  reachable (`esptool flash-id` still connects) and **one clean, uninterrupted
  re-flash restores it**. Close whatever holds the port, unplug/replug, and re-run.
- **Never run the flasher in the background / in parallel** — competing esptool
  processes fight over the COM port and cause exactly this failure.
- The `FLASH FAILED` message in `update.bat` now calls this out explicitly:
  ```
  If it said "port is busy" / "Access is denied": another program is
  holding COMx. Close any Serial Monitor / Arduino IDE / PuTTY, or a
  previous flash window, then retry. Unplug/replug the device to be sure.
  ```

### Also check `update.sh` (Linux)
Confirm the Linux port detection can't hand an **empty string** to `esptool --port`
(e.g. `grep`/`ls /dev/ttyACM*` matching nothing). The mechanism differs from Windows,
but the failure class — "empty port silently reaches esptool" — is the same. Validate
the detected port is a real `/dev/tty*` before flashing.

---

## Goal

Flash firmware to a Waveshare **ESP32-S3-Touch-AMOLED-1.75** (chip **ESP32-S3R8**,
8 MB PSRAM) over USB. The board uses the S3's **native USB-Serial/JTAG**
(USB **VID 303A / PID 1001**) and enumerates as **"USB Serial Device (COM5)"** in
Device Manager. There is **no** USB-UART bridge chip (no CP210x/CH340).

## Symptom

The `update.bat` in this folder reports **`FLASH FAILED`** on COM5. It fails **even
in ROM download mode** (hold the BOOT button while plugging in USB → the device
screen stays black = it's in the ROM bootloader). Device Manager still shows it as
`USB Serial Device (COM5)` and it disappears from Ports when unplugged, so the port
and cable are fine.

## What is known-good vs. known-bad

- **Known-good:** the exact firmware binaries flash **successfully on Linux** using
  the system `esptool` at the same offsets. So the bins are correct — **this is a
  Windows-side esptool problem, not a firmware problem.**
- **Untested before now:** the updater's *download-and-extract of esptool.exe* has
  never actually run successfully end-to-end (the Linux test used a system esptool
  already on PATH, not the downloaded one). So a **wrong `esptool.exe` path after
  `Expand-Archive`** is the #1 suspect — if the path is off, esptool never runs and
  the `.bat` still prints "FLASH FAILED."

## Files (all under `.cache\` next to `update.bat`)

- Firmware: `bootloader.bin`, `partitions.bin`, `boot_app0.bin`, `app.bin`
  - Source: https://github.com/ptbarros/NestAlert-releases/releases/latest/download/
    (also `SHA256SUMS`, `manifest.json`)
- esptool: extracted from `esptool-v5.0.0-windows-amd64.zip` (Espressif standalone,
  PyInstaller build — `esptool.exe` needs its sibling `_internal` folder/DLLs).
  - Source: https://github.com/espressif/esptool/releases/download/v5.0.0/esptool-v5.0.0-windows-amd64.zip

## Diagnose in this order

1. `dir /s .cache` — find the **real** `esptool.exe` path and confirm the whole
   PyInstaller folder came out intact. Compare it to what `update.bat` expects
   (`%WORK%\esptool-v5.0.0-windows-amd64\esptool.exe`).
2. Run esptool directly and capture the **full** output (the `.bat` hides it):
   - `esptool.exe version`
   - Minimal comms test: `esptool.exe --chip esp32s3 --port COM5 flash-id`
3. If comms fail, try reset variants (append before the subcommand):
   `--before default-reset`, then `--before usb-reset`, then — in manual download
   mode — `--before no-reset`.
4. Confirm nothing else is holding COM5 (Arduino IDE / PuTTY / a serial monitor).
5. Confirm Windows Defender/SmartScreen didn't quarantine `esptool.exe`.

## The actual flash command (esptool v5 uses hyphenated subcommands)

```
esptool.exe --chip esp32s3 --port COM5 --baud 921600 write-flash 0x0 bootloader.bin 0x8000 partitions.bin 0xe000 boot_app0.bin 0x10000 app.bin
```

Run it from the folder that contains the four `.bin` files (or use full paths).
Success looks like **"Hash of data verified"** four times, then **"Hard resetting"**.

## HARD CONSTRAINTS — do not wipe device config

- Do **NOT** run `erase-flash`.
- Do **NOT** flash any 4 MB `merged.bin`.
- Write **only** those four files at those four offsets. Anything else risks erasing
  the device's saved WiFi / token / device-name (NVS at 0x9000) and the nest cache
  (LittleFS at 0x310000), which must be preserved.

## Report back

Capture the **exact esptool error text** from step 2/3 and send it to Paul. The fix
(a path bug in `update.bat`, a `--before` reset flag, or a Defender exception) will
be baked into `update.bat` and re-published so it works for every device, not just
this machine.
