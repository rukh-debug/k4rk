"""Hardware brightness for Linux backlights and DRM-connected DDC/CI monitors.

Each invocation rediscovers the device before writing: I2C bus numbers can change
after reconnecting a monitor. No shell commands or elevated privileges are used.
"""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

BACKLIGHT = Path("/sys/class/backlight")
DRM = Path("/sys/class/drm")
DEV = Path("/dev")


def run(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=6,
                                env=dict(os.environ, LC_ALL="C"))
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError("Display did not respond. Check its power and DDC/CI setting.") from exc
    if result.returncode:
        raise RuntimeError("Brightness command failed. Check device permissions and DDC/CI.")
    return result.stdout


def monitor_name(edid, connector):
    for offset in range(54, min(len(edid), 126), 18):
        block = edid[offset:offset + 18]
        if block[:5] == b"\x00\x00\x00\xfc\x00":
            name = block[5:18].decode("ascii", errors="replace").strip(" \n\x00")
            if name:
                return name + " · " + connector
    return "External display · " + connector


def devices():
    found = []
    for path in sorted(BACKLIGHT.glob("*")):
        found.append(dict(id="backlight:" + path.name, name="Laptop display" if not found
                          else "Backlight · " + path.name, kind="backlight", device=path.name))
    for path in sorted(DRM.glob("card*-*")):
        try:
            if (path / "status").read_text().strip() != "connected":
                continue
            connector = path.name.split("-", 1)[1]
            if connector.startswith(("eDP-", "LVDS-", "DSI-")):
                continue
            edid = (path / "edid").read_bytes()
            # Include the connector to distinguish identical, serial-less displays.
            identity = hashlib.sha256(edid).hexdigest()[:16] + ":" + connector
            bus_name = (path / "ddc").resolve().name
            bus = int(bus_name[4:]) if re.fullmatch(r"i2c-\d+", bus_name) else None
            found.append(dict(id="ddc:" + identity, name=monitor_name(edid, connector),
                              kind="ddc", bus=bus))
        except (OSError, ValueError):
            continue
    return found


def check(device):
    binary = "brightnessctl" if device["kind"] == "backlight" else "ddcutil"
    if not shutil.which(binary):
        raise RuntimeError("Install " + binary + " to control this display.")
    if device["kind"] == "ddc":
        bus = device["bus"]
        if bus is None:
            raise RuntimeError("This display connection does not expose DDC/CI.")
        node = DEV / ("i2c-" + str(bus))
        if not node.exists():
            raise RuntimeError("Enable I²C access (hardware.i2c.enable on NixOS).")
        if not os.access(node, os.R_OK | os.W_OK):
            raise RuntimeError("I²C permission needed. Join the i2c group and log in again.")


def read_level(device):
    check(device)
    if device["kind"] == "backlight":
        path = BACKLIGHT / device["device"]
        current = int((path / "brightness").read_text())
        maximum = int((path / "max_brightness").read_text())
    else:
        output = run(["ddcutil", "--bus", str(device["bus"]), "--brief", "getvcp", "10"])
        match = re.search(r"^VCP\s+10\s+C\s+(\d+)\s+(\d+)\s*$", output, re.MULTILINE)
        if not match:
            raise RuntimeError("Brightness is unavailable. Enable DDC/CI in the monitor menu.")
        current, maximum = map(int, match.groups())
    if maximum <= 0 or current < 0 or current > maximum:
        raise RuntimeError("Display returned an invalid brightness range.")
    return current, maximum


def inspect(device):
    result = {**device, "available": False, "value": 0, "error": ""}
    try:
        current, maximum = read_level(device)
        result.update(available=True, value=round(current * 100 / maximum))
    except (OSError, ValueError, RuntimeError) as exc:
        result["error"] = str(exc)
    return result


def set_level(device, percent):
    if not math.isfinite(percent):
        raise ValueError("Brightness must be a finite number.")
    percent = max(1, min(100, percent))
    _, maximum = read_level(device)
    raw = max(1, round(percent * maximum / 100))
    if device["kind"] == "backlight":
        run(["brightnessctl", "--class=backlight", "--device", device["device"], "set", str(raw)])
    else:
        run(["ddcutil", "--bus", str(device["bus"]), "setvcp", "10", str(raw)])
    return inspect(device)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["discover", "read", "set"])
    parser.add_argument("target", nargs="?")
    parser.add_argument("value", nargs="?", type=float)
    args = parser.parse_args()
    try:
        found = devices()
        if args.action == "discover":
            result = {"displays": [inspect(device) for device in found]}
        else:
            device = next((d for d in found if d["id"] == args.target), None)
            if device is None:
                raise RuntimeError("Display disconnected. Choose another display.")
            if args.action == "set" and args.value is None:
                raise ValueError("A brightness value is required.")
            result = {"display": set_level(device, args.value) if args.action == "set" else inspect(device)}
    except (OSError, ValueError, RuntimeError) as exc:
        result = {"error": str(exc)}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
