"""Run actual QML controls and write scheduling against fake brightness hardware."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-brightness-") as directory:
        root = Path(directory)
        for name in ("api", "core", "services", "plugins", "widgets", "assets"):
            (root / name).symlink_to(ROOT / name)
        (root / "tools").mkdir()
        for script in (ROOT / "tools").iterdir():
            (root / "tools" / script.name).symlink_to(
                ROOT / "tools/fixtures/brightness_fake.py" if script.name == "brightness.py" else script)
        (root / "shell.qml").write_text((ROOT / "tools/system-test.qml").read_text())
        state = root / "home/.local/state/k4"
        state.mkdir(parents=True)
        catalog = json.loads((ROOT / "plugins/catalog.json").read_text())
        (state / "plugins.json").write_text(json.dumps({"habilitados": {p["id"]: False for p in catalog["plugins"]}}))
        env = dict(os.environ, HOME=str(root / "home"), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_QPA_PLATFORM="wayland",
                   QT_QUICK_BACKEND="software", HYPRLAND_INSTANCE_SIGNATURE="k4-test-no-compositor",
                   QT_NO_XDG_DESKTOP_PORTAL="1", K4_SYSTEM_TEST_SUITE=str(ROOT / "tools/tst_brightness.qml"),
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""))
        result = subprocess.run(["dbus-run-session", "--", "quickshell", "-p", str(root / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=50)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "FAIL!", "timed out", "Failed to load configuration")
        if result.returncode or "Brightness UI:" not in output or any(error in output for error in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
