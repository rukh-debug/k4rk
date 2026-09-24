#!/usr/bin/env python3
"""Reject reintroduced split preferences and missing host schema entries."""
from pathlib import Path
import re
import sys
from config_schema import SHELL_DEFAULTS, LOCAL_SHELL_DEFAULTS

ROOT = Path(__file__).resolve().parent.parent


def check():
    errors = []
    settings = (ROOT / "services/Settings.qml").read_text()
    properties = set(re.findall(r"^    property (?:bool|int|real|string|var) (\w+):", settings, re.M))
    internal = {"cargado", "loadingConfig", "savedConfig", "defaults", "settingsConnected", "popupSizePreview"}
    declared = set(SHELL_DEFAULTS) | set(LOCAL_SHELL_DEFAULTS)
    if properties - internal != declared:
        errors.append("Host properties and declared storage ownership disagree: " +
                      str(sorted((properties - internal) ^ declared)))
    for directory in ("services", "api", "plugins", "ejemplos"):
        for path in (ROOT / directory).rglob("*.qml"):
            text = re.sub(r"//[^\n]*", "", path.read_text())
            if re.search(r"\.config/k4term/(?:hosts|claves)\.json", text):
                errors.append(str(path.relative_to(ROOT)) + ": retired SSH store")
            if path.name != "Ambiente.qml" and re.search(r"\.setText\(JSON\.stringify", text):
                errors.append(str(path.relative_to(ROOT)) + ": direct JSON writer; use the shared store")
    return errors


if __name__ == "__main__":
    errors = check()
    print("\n".join(errors) if errors else "Configuration ownership checks passed.")
    sys.exit(bool(errors))
