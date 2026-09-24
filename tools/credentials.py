#!/usr/bin/env python3
"""Secret Service access. Secret values travel over stdin/stdout, never argv."""

import json
import subprocess
import sys


def request(action, plugin, account, value=""):
    if action not in ("get", "set", "delete") or not plugin or not account:
        raise ValueError("Invalid credential request")
    verbs = {"get": "lookup", "set": "store", "delete": "clear"}
    command = ["secret-tool", verbs[action]]
    if action == "set":
        command += ["--label=k4 " + plugin]
    command += ["application", "k4", "plugin", plugin, "account", account]
    try:
        result = subprocess.run(command, input=value if action == "set" else "",
                                capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RuntimeError("System keyring unavailable; credentials are session-only") from error
    if result.returncode:
        if action in ("get", "delete") and result.returncode == 1 and not result.stderr.strip():
            return ""
        raise RuntimeError("System keyring unavailable or locked; credentials are session-only")
    return result.stdout.removesuffix("\n") if action == "get" else ""


def main():
    try:
        data = json.loads(sys.stdin.readline())
        value = request(data["action"], data["plugin"], data["account"], data.get("value", ""))
        print(json.dumps(dict(value=value)))
    except (ValueError, KeyError, RuntimeError):
        print(json.dumps(dict(error="System keyring unavailable or locked; credentials are session-only")))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
