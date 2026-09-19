#!/usr/bin/env python3
"""Exercise popup allocation and live QML contracts with a private home.

Run in a Wayland session: nix develop -c python3 tools/test_popup_ui.py
The lifecycle checks briefly map test islands, then destroy them.
"""

import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-popup-") as directory:
        root = Path(directory)
        home = root / "home"
        home.mkdir()
        (root / "shell.qml").write_text((ROOT / "tools/popup-test.qml").read_text())
        env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_QPA_PLATFORM="wayland",
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""),
                   K4_POPUP_TEST_SUITE=str(ROOT / "tools/tst_popup.qml"))
        result = subprocess.run(["quickshell", "-p", str(root / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=30)
        print(result.stdout, end="")
        print(result.stderr, end="")
        output = result.stdout + result.stderr
        errors = ("FAIL!", "TypeError:", "ReferenceError:", "Unable to assign",
                  "Binding loop", "Error loading configuration", "is not available")
        if result.returncode or "Popup tests:" not in output or any(e in output for e in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
