#!/usr/bin/env bash
#  k4 dev loop: build the flake, swap the running bar for the new build.
#
#      tools/dev.sh             build and restart
#      tools/dev.sh --no-build  restart the build the mirror last ran
#
#  Three traps this script exists to never step in again:
#    - Kill by exact process name (`pgrep -x`). The engine runs as
#      the wrapped store binary, whose comm is truncated to
#      `.quickshell-wra` — the exact-name kill never matched it and
#      the survivor drew a second bar on the screen. Every instance
#      is swept by BOTH names it goes by: its argv (`quickshell -p …`)
#      and its comm (anything containing «quickshell»).
#    - A plain `pkill -f quickshell` also matches the shell running
#      that very line, because its own argv contains the word — and
#      takes the terminal down with it. The bracket in `[-]p` keeps
#      the pattern from matching the line that spells it.
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
#  Walk /proc directly instead of trusting pgrep's flags — the same
#  walk `k4 kill` does, kept here so the dev loop works even against
#  a store path older than that subcommand. An instance is a process
#  whose argv says «quickshell -p …» or whose comm contains
#  «quickshell» (the wrapped store binary truncates to
#  `.quickshell-wra`, which an exact-name kill never matched — the
#  survivor drew a second bar). Launcher shells are not matched:
#  they exec into the engine or die with it, and a looser pattern
#  kills processes that merely mention a path in their command line.
#  The matcher cannot match the very shell spelling it: this
#  script's own argv is «bash tools/dev.sh».
bar_pids() {
    local d pid cmd comm
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        [ "$pid" = "$$" ] && continue
        #  stderr is silenced BEFORE the input redirect: redirections
        #  apply left to right, and a /proc entry vanishing between
        #  the listing and the read would otherwise shout about it.
        cmd="$(tr '\0' ' ' 2>/dev/null < "$d/cmdline")" || true
        case "$cmd" in
            *"quickshell -p"*) echo "$pid"; continue ;;
        esac
        comm="$(cat "$d/comm" 2>/dev/null)" || true
        case "$comm" in
            *quickshell*) echo "$pid"; continue ;;
        esac
    done
    return 0
}

PIDS="$(bar_pids | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// /}" ]; then
    echo "==> killing: $PIDS"
    #  Deliberately unquoted: one pid per word.
    kill -9 $PIDS 2>/dev/null || true
    for _ in $(seq 1 30); do
        bar_pids | grep -q . || break
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
#  The first answer can beat the catalog: user plugins register a beat
#  after the repo's own, and a count taken too early reads as plugins
#  gone missing. Let it settle and ask again — the later answer wins.
sleep 1.2
SETTLED="$(quickshell ipc -p "$MIRROR/shell.qml" call k4 pluginStatus 2>/dev/null || true)"
case "$SETTLED" in \[*\]*) OUT="$SETTLED" ;; esac
echo "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
errs = [p for p in d if p.get("error")]
print("plugins: %d  errors: %d" % (len(d), len(errs)))
for e in errs:
    print("  %s: %s" % (e["id"], e["error"]))'
