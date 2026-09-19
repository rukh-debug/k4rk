"""Checked power-profile operations; the system daemon owns the actual policy."""

import json
import subprocess
import sys

PROFILES = ("power-saver", "balanced", "performance")


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=12)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Power service unavailable")
    return result.stdout


def inspect():
    raw = json.loads(run([
        "busctl", "--system", "--json=short", "call",
        "org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles",
        "org.freedesktop.DBus.Properties", "GetAll", "s", "org.freedesktop.UPower.PowerProfiles",
    ]))["data"][0]
    return {
        "available": True,
        "profile": raw["ActiveProfile"]["data"],
        "profiles": [p["Profile"]["data"] for p in raw["Profiles"]["data"]
                     if p["Profile"]["data"] in PROFILES],
        "degraded": raw.get("PerformanceDegraded", {}).get("data", ""),
        "holds": [{k: v["data"] for k, v in hold.items()}
                  for hold in raw.get("ActiveProfileHolds", {}).get("data", [])],
    }


def main(args):
    requested = args[0] if args else "inspect"
    if requested != "inspect":
        if requested not in PROFILES:
            raise ValueError("Unknown power profile")
        if requested not in inspect()["profiles"]:
            raise ValueError("This power profile is not supported on this device")
        run(["powerprofilesctl", "set", requested])
    state = inspect()
    if requested != "inspect" and state["profile"] != requested:
        state["error"] = "The power service did not apply the requested profile"
    return state


if __name__ == "__main__":
    try:
        print(json.dumps(main(sys.argv[1:])))
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"error": str(exc)}))
        sys.exit(1)
