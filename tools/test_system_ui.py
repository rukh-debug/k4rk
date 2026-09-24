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
import sys
from test_config_helpers import write_settings

ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-system-") as directory:
        root = Path(directory)
        (root / "tools").symlink_to(ROOT / "tools")
        (root / "shell.qml").write_text((ROOT / "tools/system-test.qml").read_text())
        clipboard = root / "wl-copy"
        clipboard.write_text("#!" + sys.executable + "\nimport pathlib, sys\npathlib.Path(" + repr(str(root / "copied-config.json")) + ").write_text(sys.stdin.read())\n")
        clipboard.chmod(0o700)
        keyring = root / "secret-tool"
        keyring.write_text("#!" + sys.executable + "\n" + '''import json, pathlib, sys, time
path = pathlib.Path(__file__).with_name("test-keyring.json")
data = json.loads(path.read_text()) if path.exists() else {}
key = sys.argv[sys.argv.index("plugin") + 1] + "/" + sys.argv[sys.argv.index("account") + 1]
if key.endswith("/locked") and not path.with_suffix(".unlocked").exists():
    path.with_suffix(".unlocked").touch()
    print("Keyring locked", file=sys.stderr)
    sys.exit(2)
if sys.argv[1] == "lookup":
    time.sleep(0.1)
    print(data.get(key, "old-secret"))
else:
    data[key] = sys.stdin.read() if sys.argv[1] == "store" else ""
    path.write_text(json.dumps(data))
''')
        keyring.chmod(0o700)
        home = root / "home"
        home.mkdir()
        write_settings(home)
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), XDG_STATE_HOME=str(home / ".local/state"), XDG_CACHE_HOME=str(root / "cache"),
                   PATH=str(root) + os.pathsep + os.environ.get("PATH", ""),
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
        copied = json.loads((root / "copied-config.json").read_text())
        assert copied["schemaVersion"] == 2 and isinstance(copied["shell"], dict)
        assert not set(copied) & {"cache", "retired", "migration", "revision"}
        assert all(set(plugin) <= {"enabled", "settings"} for plugin in copied["plugins"].values())
        assert "secret-after-reload" not in json.dumps(copied)
        secrets = json.loads((root / "test-keyring.json").read_text())
        assert secrets["credential-test/first"] == "secret-after-reload"
        assert secrets["ssh/fixture-host"] == "ssh-test-secret"


if __name__ == "__main__":
    main()
