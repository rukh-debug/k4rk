"""Private settings fixtures for real QML tests; never uses the session home."""
import json
from pathlib import Path


def write_settings(home, preferences=None):
    root = Path(__file__).resolve().parent.parent
    catalog = json.loads((root / "plugins/catalog.json").read_text())
    plugins = {plugin["id"]: {"enabled": False} for plugin in catalog["plugins"]}
    for ident, values in (preferences or {}).items():
        plugins.setdefault(ident, {})["settings"] = values
    path = Path(home) / ".config/k4/config.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(dict(schemaVersion=2, shell={}, features={}, plugins=plugins)))
    return path
