"""Exercise real QML layout/navigation with private settings and no display IPC."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-power-display-") as directory:
        root = Path(directory)
        for name in ("tools", "api", "core", "services", "plugins", "widgets"):
            (root / name).symlink_to(ROOT / name)
        (root / "shell.qml").write_text((ROOT / "tools/system-test.qml").read_text())
        state = root / "home/.local/state/k4"
        state.mkdir(parents=True)
        catalog = json.loads((ROOT / "plugins/catalog.json").read_text())
        (state / "plugins.json").write_text(json.dumps({"habilitados": {p["id"]: False for p in catalog["plugins"]}}))
        env = dict(os.environ, HOME=str(root / "home"), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_QPA_PLATFORM="wayland",
                   QT_QUICK_BACKEND="software", HYPRLAND_INSTANCE_SIGNATURE="k4-test-no-compositor",
                   QT_NO_XDG_DESKTOP_PORTAL="1",
                   K4_SYSTEM_TEST_SUITE=str(ROOT / "tools/tst_power_display.qml"),
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""))
        result = subprocess.run(["dbus-run-session", "--", "quickshell", "-p", str(root / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=50)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "FAIL!", "timed out", "Failed to load configuration")
        if result.returncode or "Power/display UI:" not in output or any(error in output for error in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
