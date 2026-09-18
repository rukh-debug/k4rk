#!/usr/bin/env python3
"""Run the System monitor against real QML and kernel data, with private state.

Use the packaged Quickshell and Qt environment (the same versions as k4).
The test layer is transparent and has no input region; no visual verdict is made.
"""
import os
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-system-") as directory:
        root = Path(directory)
        (root / "tools").symlink_to(ROOT / "tools")
        (root / "shell.qml").write_text((ROOT / "tools/system-test.qml").read_text())
        home = root / "home"
        home.mkdir()
        state = home / ".local/state/k4"
        state.mkdir(parents=True)
        catalog = json.loads((ROOT / "plugins/catalog.json").read_text())
        (state / "plugins.json").write_text(json.dumps({"habilitados": {p["id"]: False for p in catalog["plugins"]}}))
        env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_NO_XDG_DESKTOP_PORTAL="1",
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""),
                   K4_SYSTEM_TEST_SUITE=str(ROOT / "tools/tst_system.qml"))
        result = subprocess.run(["dbus-run-session", "--", "quickshell", "-p", str(root / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=50)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "unavailable", "FAIL!", "timed out")
        if result.returncode or "System UI:" not in output or any(error in output for error in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
