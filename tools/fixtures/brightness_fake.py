"""Deterministic hardware stand-in used only by the isolated QML tests."""
import json
from pathlib import Path
import sys
import time

path = Path.home() / "brightness-fixture.json"
displays = json.loads(path.read_text()) if path.exists() else [
    dict(id="backlight:mock", name="Laptop display", kind="backlight", value=50, available=True, error=""),
    dict(id="ddc:mock", name="Test monitor · HDMI-A-1", kind="ddc", value=70, available=True, error=""),
]
action = sys.argv[1]
if action == "discover":
    result = {"displays": displays}
else:
    display = next(d for d in displays if d["id"] == sys.argv[2])
    if action == "set":
        time.sleep(0.15)
        if int(sys.argv[3]) == 13:
            print(json.dumps({"error": "Simulated DDC write failure"}))
            sys.exit(0)
        display["value"] = int(sys.argv[3])
        path.write_text(json.dumps(displays))
    result = {"display": display}
print(json.dumps(result))
