"""Check helper-to-service-to-view shortcut records with private configuration.

Requires Wayland and the matching Quickshell/Qt environment. The test surface
is transparent and has no input region; this is not a visual verification.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
from test_config_helpers import write_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-shortcuts-ui-") as directory:
        root = Path(directory)
        home = root / "home"
        config = home / ".config/hypr"
        config.mkdir(parents=True)
        write_settings(home)
        (config / "hyprland.lua").write_text(
            '-- Windows\n'
            'hl.bind("SUPER + Q", hl.dsp.window.close())\n'
            'hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm app -- terminal"))\n'
            '-- Media\n'
            'hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))\n')
        (root / "tools").mkdir()
        (root / "tools/shortcuts.py").symlink_to(ROOT / "tools/shortcuts.py")
        for name in ("config_store.py", "config_schema.py", "migrate_config.py", "config_outputs.py", "credentials.py", "monitors.py"):
            (root / "tools" / name).symlink_to(ROOT / "tools" / name)
        (root / "shell.qml").write_text((ROOT / "tools/shortcuts-test.qml").read_text())
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                   XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_QPA_PLATFORM="wayland",
                   QT_NO_XDG_DESKTOP_PORTAL="1",
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""),
                   K4_SHORTCUTS_TEST_SUITE=str(ROOT / "tools/tst_shortcuts.qml"))
        result = subprocess.run(["dbus-run-session", "--", "quickshell", "-p", str(root / "shell.qml")],
                                env=env, capture_output=True, text=True, timeout=25)
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop",
                  "Error loading configuration", "FAIL!", "timed out")
        if (result.returncode or "Shortcuts UI:" not in output
                or any(error in output for error in errors)):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
