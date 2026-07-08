# NestAlert device updater

One-click firmware updates for NestAlert turtle-nest alert devices. No
programming tools needed — this downloads the latest firmware and flashes it to a
device over a USB cable.

## First-time setup (once per laptop)

1. Click the green **`< > Code`** button above → **Download ZIP**.
2. Unzip it somewhere easy, like the Desktop.

That's it. (You need an internet connection the first time so it can fetch the
flashing tool.)

## Updating a device

1. Plug the device into the laptop with a USB cable.
2. Run the updater:
   - **Windows:** double-click **`update.bat`**
   - **Linux:** open a terminal in this folder and run `./update.sh`
3. When it says *"Plug in ONE device, press ENTER"*, press **Enter**.
4. Wait for **✅ SUCCESS**.
5. To update another device: unplug this one, plug in the next, press **Enter** again.
6. Type **`q`** and press Enter when you're done.

## How to confirm it worked

On the device, press the **BOOT button** to cycle screens until you reach the
status screen showing **`Ver: v7.x`**. It should match the version the updater
printed (e.g. `v7.3`).

## Good to know

- **Your settings are safe.** Flashing only replaces the program. It does **not**
  erase each device's WiFi network, token, device name, or the saved nest list.
- **One device at a time.** Flash them one after another; don't plug in several at once.
- **If a flash fails:** try a different USB cable or USB port and run it again.
  A failed flash doesn't harm the device — just retry.
- **Linux first-time only** — if you see *"Path '/dev/ttyACM0' is not readable"*, your
  user needs access to the USB serial port. Run this once, then **log out and back in**:
  ```
  sudo usermod -aG dialout $USER
  ```
- Firmware versions and release notes are on the **Releases** page (right-hand side
  of this repo).

## Getting a new version

When there's a firmware update, Paul publishes it here and it becomes the new
"latest" automatically — just run the updater again and it picks it up.
