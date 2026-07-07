#!/usr/bin/env bash
#
# NestAlert field updater (Linux / macOS).
# Downloads the latest published firmware and flashes it to a device over USB.
# Nothing to pre-install: fetches a standalone esptool on first run if needed.
# Flashing does NOT erase device config (WiFi / token / name) or the nest cache —
# it writes only the app/bootloader/partitions, never the NVS or data regions.
#
set -uo pipefail

RELEASES_REPO="ptbarros/NestAlert-releases"
BASE="https://github.com/${RELEASES_REPO}/releases/latest/download"
ESPTOOL_VER="v5.0.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.cache"
mkdir -p "$WORK"

echo "==================================================="
echo "   NestAlert device updater"
echo "==================================================="

# --- 1. esptool: use one on PATH, else download the standalone build ----------
# NOTE: the v5.0.0 archive unpacks to a folder WITHOUT the version in its name
# (e.g. "esptool-linux-amd64"), so locate the binary by searching the cache
# rather than assuming a fixed path.
if command -v esptool >/dev/null 2>&1; then
  ESPTOOL="esptool"
else
  case "$(uname -s)" in
    Darwin) ARCH="macos" ;;
    *)      ARCH="linux-amd64" ;;
  esac
  ESPTOOL="$(find "$WORK" -type f -name esptool 2>/dev/null | head -1)"
  if [ -z "$ESPTOOL" ]; then
    echo ">> downloading esptool ${ESPTOOL_VER} (one time) ..."
    curl -fL "https://github.com/espressif/esptool/releases/download/${ESPTOOL_VER}/esptool-${ESPTOOL_VER}-${ARCH}.tar.gz" -o "$WORK/esptool.tgz" \
      && tar -xzf "$WORK/esptool.tgz" -C "$WORK" \
      || { echo "Could not download esptool. Check the internet connection."; exit 1; }
    ESPTOOL="$(find "$WORK" -type f -name esptool 2>/dev/null | head -1)"
  fi
  [ -n "$ESPTOOL" ] || { echo "Could not locate esptool after extracting."; exit 1; }
  chmod +x "$ESPTOOL" 2>/dev/null || true
fi

# --- 2. fetch the latest firmware + checksums --------------------------------
echo ">> fetching latest firmware ..."
for f in manifest.json SHA256SUMS bootloader.bin partitions.bin boot_app0.bin app.bin; do
  curl -fL "$BASE/$f" -o "$WORK/$f" || { echo "Download failed ($f). Check the internet connection."; exit 1; }
done
VERSION="$(grep '"version"' "$WORK/manifest.json" | sed -E 's/.*"version": *"([^"]+)".*/\1/')"
echo ">> firmware version: ${VERSION}"

# --- 3. verify the downloads (guards against a corrupted/partial download) ----
if ! ( cd "$WORK" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
  echo "CHECKSUM MISMATCH — download looks corrupted. Re-run to try again."; exit 1
fi
echo ">> checksums OK"

# --- 4. flash loop (one device at a time) ------------------------------------
detect_port() { for p in /dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem*; do [ -e "$p" ] && { echo "$p"; return 0; }; done; return 1; }

while true; do
  echo
  read -r -p "Plug in ONE device, then press ENTER to flash it (or type q to quit): " ans
  [ "$ans" = "q" ] || [ "$ans" = "Q" ] && break
  PORT="$(detect_port)" || { echo "!! No device found on USB — check the cable and try again."; continue; }
  echo ">> flashing ${VERSION} to ${PORT} ..."
  if "$ESPTOOL" --chip esp32s3 --port "$PORT" --baud 921600 write-flash \
        0x0 "$WORK/bootloader.bin" 0x8000 "$WORK/partitions.bin" \
        0xe000 "$WORK/boot_app0.bin" 0x10000 "$WORK/app.bin"; then
    echo
    echo "   ✅ SUCCESS — flashed ${VERSION}."
    echo "      Confirm: the device's PMU screen should show Ver: ${VERSION}"
  else
    echo
    echo "   ❌ FLASH FAILED — try a different USB cable/port, then retry."
  fi
done
echo "Done."
