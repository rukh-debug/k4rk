#!/usr/bin/env bash
#  k4 dev loop: build the flake, swap the running bar for the new build.
#
#      tools/dev.sh             build and restart
#      tools/dev.sh --no-build  restart the build the mirror last ran
#
#  Two traps this script exists to never step in again:
#    - Kill by exact process name (`pgrep -x`). A `pkill -f quickshell`
#      also matches the shell running that very line, because its own
#      argv contains the word — and takes the terminal down with it.
#    - SIGKILL cycles leave stale instance locks in
#      $XDG_RUNTIME_DIR/quickshell/by-id; IPC then answers "not ready"
#      forever, so the directory is cleared after every kill.

set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MIRROR="$HOME/.local/share/k4/code"
LOG="${TMPDIR:-/tmp}/k4-dev.log"

BUILD=1
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# ── which store path to run ─────────────────────────────────────────
if (( BUILD )); then
    echo "==> building .#k4"
    STORE="$(cd "$RAIZ" && nix build .#k4 --no-link --print-out-paths | tail -1)"
else
    ORIGEN="$(cat "$MIRROR/.k4-origen" 2>/dev/null || true)"
    if [ -z "$ORIGEN" ]; then
        echo "nothing recorded in $MIRROR/.k4-origen — run once without --no-build" >&2
        exit 1
    fi
    STORE="${ORIGEN%/share/k4}"
fi
BIN="$STORE/bin/k4"

if [ ! -x "$BIN" ]; then
    echo "no k4 binary at $BIN" >&2
    exit 1
fi
echo "==> running $STORE"

# ── out with the old ────────────────────────────────────────────────
PIDS="$(pgrep -x quickshell || true)"
if [ -n "$PIDS" ]; then
    kill -9 $PIDS 2>/dev/null || true
    for _ in $(seq 1 30); do
        pgrep -x quickshell >/dev/null || break
        sleep 0.1
    done
fi
rm -rf "$RUNTIME/quickshell/by-id"

# ── in with the new ─────────────────────────────────────────────────
nohup setsid "$BIN" --no-duplicate </dev/null >>"$LOG" 2>&1 &
disown

# ── health: plugins up, none in error ───────────────────────────────
echo "==> waiting for IPC (log: $LOG)"
OUT=""
for _ in $(seq 1 50); do
    [ -f "$MIRROR/shell.qml" ] && OUT="$(quickshell ipc -p "$MIRROR/shell.qml" call k4 pluginStatus 2>/dev/null || true)"
    #  Quickshell answers plain text ("No running instances…") until
    #  IPC is really up; only a JSON array counts as an answer.
    case "$OUT" in \[*\]*) break ;; *) OUT="" ;; esac
    sleep 0.3
done
if [ -z "$OUT" ]; then
    echo "!! IPC never answered; check $LOG and $HOME/.local/state/k4/k4.log" >&2
    exit 1
fi
echo "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
errs = [p for p in d if p.get("error")]
print("plugins: %d  errors: %d" % (len(d), len(errs)))
for e in errs:
    print("  %s: %s" % (e["id"], e["error"]))'
