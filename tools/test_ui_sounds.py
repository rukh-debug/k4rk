#!/usr/bin/env python3
"""Test the real sound service with isolated settings/audio state and muted players."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def main():
    with tempfile.TemporaryDirectory(prefix="k4-ui-sounds-") as directory:
        root = Path(directory)
        services = root / "services"
        services.mkdir()
        tools = root / "tools"
        tools.mkdir()
        (root / "assets").symlink_to(ROOT / "assets")
        shutil.copyfile(ROOT / "services/UiSounds.qml", services / "UiSounds.qml")
        (services / "qmldir").write_text(
            "singleton UiSounds 1.0 UiSounds.qml\n"
            "singleton Settings 1.0 Settings.qml\n"
            "singleton Audio 1.0 Audio.qml\n"
        )
        (services / "Settings.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property bool cargado: true
    property bool uiSoundsEnabled: true
    property int uiSoundVolume: 35
}
""")
        (services / "Audio.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property var salidaActiva: ({ audio: {} })
    property bool muted: false
    property int volume: 50
}
""")
        shutil.copyfile(ROOT / "tools/tst_ui_sounds.qml", tools / "tst_ui_sounds.qml")
        (root / "shell.qml").write_text(
            (ROOT / "tools/ui-controls-test.qml").read_text().replace(
                '"tst_ui_controls.qml"', '"tools/tst_ui_sounds.qml"'
            )
        )
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   QML_IMPORT_PATH=str(ROOT / "api") + ":" + os.environ.get("QML_IMPORT_PATH", ""))
        result = subprocess.run(
            ["quickshell", "-p", str(root / "shell.qml")],
            env=env, capture_output=True, text=True, timeout=30,
        )
        output = result.stdout + result.stderr
        print(output, end="")
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop",
                  "FAIL!", "timed out", "Failed to load configuration", "Error decoding")
        if result.returncode or "UI sound service:" not in output or any(e in output for e in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
