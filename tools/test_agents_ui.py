#!/usr/bin/env python3
"""Run real QML controls/process races with a private home and fake quota worker."""

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

# Ignore termination long enough to return an obsolete response. This proves
# that the owner discards it, rather than relying on process cancellation.
WORKER = '''import json, os, signal, sys, time
if "--catalog" in sys.argv:
    os.execv(sys.executable, [sys.executable, os.environ["K4_REAL_AGENTS_HELPER"]] + sys.argv[1:])
signal.signal(signal.SIGTERM, lambda *args: None)
providers = sys.argv[sys.argv.index("--providers") + 1].split(",")
with open(os.path.join(os.environ["HOME"], "queries.jsonl"), "a") as log:
    log.write(json.dumps(providers) + "\\n")
time.sleep(0.4)
print(json.dumps({"agentes": [{"id": ident, "nombre": ident, "limites": [
    {"nombre": "5 hours", "pct": 99, "reinicia": None, "activo": True}]} for ident in providers]}))
'''


def main():
    with tempfile.TemporaryDirectory(prefix="k4-agents-ui-") as directory:
        root = Path(directory)
        home = root / "home"
        for ident, state in (("agents", {"providers": [], "warn": False, "threshold": 95,
                                          "live": False, "pinnedQuota": "codex:weekly"}),
                             ("agentes", {"avisar": True, "umbral": 70, "enVivo": True})):
            path = home / ".local/state/k4/plugins" / ident / "estado.json"
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps(state))
        (root / "shell.qml").write_text((ROOT / "tools/agents-test.qml").read_text())
        (root / "tools").mkdir()
        (root / "tools/agents.py").write_text(WORKER)
        env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(root / "cache"),
                   XDG_DATA_HOME=str(root / "data"), QT_QPA_PLATFORM="offscreen",
                   QML_IMPORT_PATH=str(ROOT / "api"),
                   K4_AGENTS_TEST_SUITE=str(ROOT / "tools/tst_agents.qml"),
                   K4_REAL_AGENTS_HELPER=str(ROOT / "tools/agents.py"))
        result = subprocess.run(["quickshell", "-p", str(root / "shell.qml")], env=env,
                                capture_output=True, text=True, timeout=40)
        print(result.stdout, end="")
        print(result.stderr, end="")
        # No saved-off CLI should ever be discovered, including at startup.
        queries = home / "queries.jsonl"
        if queries.exists():
            for line in queries.read_text().splitlines():
                if set(json.loads(line)) & {"claude", "codex"}:
                    raise AssertionError("Queried a saved-off provider")
        output = result.stdout + result.stderr
        errors = ("TypeError:", "ReferenceError:", "Unable to assign", "Binding loop", "Error loading configuration")
        if result.returncode or "Agents UI:" not in output or any(error in output for error in errors):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
