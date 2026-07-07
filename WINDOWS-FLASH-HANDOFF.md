# Windows flashing — debugging handoff

> **✅ RESOLVED (2026-07-06).** Root cause: the esptool v5.0.0 archive unpacks to a
> folder **without** the version in its name (`esptool-windows-amd64` /
> `esptool-linux-amd64`), but `update.bat`/`update.sh` looked for
> `esptool-v5.0.0-...`. That path didn't exist, so a non-existent binary "ran,"
> errored instantly, and was mislabeled as a flash failure (sending you chasing the
> BOOT button). The device, cable, baud, and USB reset were all fine. **Both scripts
> now find `esptool.exe`/`esptool` by searching the cache**, so re-download the ZIP and
> run again — it should flash straight to COM5, no BOOT button needed. The notes below
> are kept as a record of the diagnosis.

---


Hand this to a Claude Code (or any assistant) running on the Windows PC that's
failing to flash a NestAlert device. It has everything needed to diagnose without
prior context.

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
