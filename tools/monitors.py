#!/usr/bin/env python3
"""Hyprland Lua monitor discovery and independently supervised preview transactions.

The detached transaction process owns the lock, deadline and confirmation socket.
QML may disappear at any point without cancelling recovery. Only Keep writes the
confirmed include. All subprocess calls use argv, never a shell.
"""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid


MODE = re.compile(r"^(\d+)x(\d+)@([\d.]+)(?:Hz)?$")
ACTIVE = {"starting", "applying", "testing", "saving", "reverting"}
TIMEOUT = 15


def atomic(path, text):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".monitor-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return default


def locations():
    session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not session:
        raise ValueError("A running Hyprland session is required.")
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR is required for monitor recovery.")
    key = hashlib.sha256(session.encode()).hexdigest()[:12]
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "k4/monitors"
    run = Path(runtime) / ("k4-monitors-" + key)
    run.mkdir(mode=0o700, parents=True, exist_ok=True)
    return state, run


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Hyprland request failed.")
    return result.stdout.strip()


def normalize(raw):
    result = []
    for item in raw:
        modes = []
        for value in item.get("availableModes", []):
            match = MODE.fullmatch(value)
            if not match:
                continue
            w, h, hz = int(match[1]), int(match[2]), float(match[3])
            mode = f"{w}x{h}@{hz:.2f}"
            if mode not in modes:
                modes.append(mode)
        w, h = item.get("width", 0), item.get("height", 0)
        rate = item.get("refreshRate", 0)
        current = min(modes, key=lambda m: abs(float(MODE.fullmatch(m)[3]) - rate)
                      if m.startswith(f"{w}x{h}@") else float("inf"), default="preferred")
        if not current.startswith(f"{w}x{h}@") and w > 0 and h > 0:
            current = f"{w}x{h}@{rate:.2f}"
        if item.get("disabled"):
            current = modes[0] if modes else "preferred"
        mirror = item.get("mirrorOf", "none")
        result.append({"name": item["name"], "description": item.get("description", item["name"]),
                       "modes": modes, "mode": current, "scale": item.get("scale", 1) or 1,
                       "x": item.get("x", 0), "y": item.get("y", 0),
                       "transform": item.get("transform", 0), "enabled": not item.get("disabled", False),
                       "mirror": "" if mirror in ("none", None, "") else str(mirror),
                       "width": w, "height": h, "refreshRate": rate})
    return sorted(result, key=lambda o: o["name"])


def discover():
    return normalize(json.loads(hypr("-j", "monitors", "all")))


FIELDS = ("name", "mode", "scale", "x", "y", "transform", "enabled", "mirror")


def editable(outputs):
    return [{key: output[key] for key in FIELDS} for output in outputs]


def fingerprint(outputs):
    return hashlib.sha256(json.dumps(editable(outputs), sort_keys=True).encode()).hexdigest()


def validate(draft, live):
    if not isinstance(draft, list) or len(draft) != len(live):
        raise ValueError("The connected monitor set changed. Refresh before applying.")
    known = {o["name"]: o for o in live}
    if len({o.get("name") for o in draft}) != len(draft) or {o.get("name") for o in draft} != set(known):
        raise ValueError("The connected monitor set changed. Refresh before applying.")
    clean = []
    for output in draft:
        name = output["name"]
        if type(output.get("enabled")) is not bool:
            raise ValueError("Enabled must be a boolean.")
        mode = output.get("mode")
        if mode != "preferred" and mode not in known[name]["modes"] and mode != known[name]["mode"]:
            raise ValueError(f"{name}: choose an advertised mode.")
        scale = output.get("scale")
        if type(scale) not in (float, int) or not math.isfinite(scale) or not 0.25 <= scale <= 8:
            raise ValueError(f"{name}: scale must be between 25% and 800%.")
        transform = output.get("transform")
        if type(transform) is not int or transform not in range(8):
            raise ValueError("Invalid orientation.")
        for axis in ("x", "y"):
            if type(output.get(axis)) is not int or abs(output[axis]) > 100000:
                raise ValueError("Positions must be whole numbers between -100000 and 100000.")
        match = MODE.fullmatch(mode)
        if output["enabled"] and match and any(abs(int(match[i]) / scale - round(int(match[i]) / scale)) > 0.001 for i in (1, 2)):
            raise ValueError(f"{name}: this scale does not produce whole logical pixels for the selected mode.")
        mirror = output.get("mirror", "")
        if mirror and (mirror == name or mirror not in known):
            raise ValueError("Choose another connected monitor as the mirror source.")
        clean.append({key: output.get(key, "") for key in FIELDS})
    independent = {o["name"] for o in clean if o["enabled"] and not o["mirror"]}
    if not independent:
        raise ValueError("Keep at least one independent monitor enabled.")
    if any(o["enabled"] and o["mirror"] and o["mirror"] not in independent for o in clean):
        raise ValueError("A mirror source must be enabled and must not itself be a mirror.")
    return sorted(clean, key=lambda o: o["name"])


def lua_string(value):
    # Lua decimal byte escapes are unambiguous, including control/non-ASCII bytes.
    return '"' + ''.join(chr(b) if 32 <= b < 127 and b not in (34, 92) else f"\\{b:03d}"
                         for b in value.encode("utf-8")) + '"'


def rule(output):
    return ("hl.monitor({ output = " + lua_string(output["name"])
            + ", mode = " + lua_string(output["mode"])
            + f", position = {lua_string(str(output['x']) + 'x' + str(output['y']))}"
            + f", scale = {output['scale']}, transform = {output['transform']}"
            + ", disabled = " + ("false" if output["enabled"] else "true")
            + ", mirror = " + lua_string(output["mirror"]) + " })")


def ordered(outputs):
    return sorted(outputs, key=lambda o: (not o["enabled"], bool(o["mirror"])))


def apply(outputs):
    reply = hypr("eval", "\n".join(rule(o) for o in ordered(outputs)))
    if reply != "ok":
        raise RuntimeError(reply or "Hyprland did not acknowledge the monitor rules.")


def matches(wanted, actual):
    by_name = {o["name"]: o for o in actual}
    if set(by_name) != {o["name"] for o in wanted}:
        return False
    for target in wanted:
        found = by_name[target["name"]]
        if target["enabled"] != found["enabled"]:
            return False
        if not target["enabled"]:
            continue
        if abs(target["scale"] - found["scale"]) > 0.001 or target["transform"] != found["transform"] or target["mirror"] != found["mirror"]:
            return False
        if not target["mirror"] and (target["x"], target["y"]) != (found["x"], found["y"]):
            return False
        if target["mode"] != "preferred":
            match = MODE.fullmatch(target["mode"])
            if (int(match[1]), int(match[2])) != (found["width"], found["height"]) or abs(float(match[3]) - found["refreshRate"]) > 0.015:
                return False
    return True


def verify(wanted, seconds=5):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if matches(wanted, discover()):
            return
        time.sleep(0.2)
    raise RuntimeError("Hyprland did not apply the requested layout. The previous layout will be restored.")


def confirmed_lua(outputs):
    lines = ["-- Generated by k4 after confirmation. Nix defaults load before this file.",
             "local connected = {}", "for _, m in ipairs(hl.get_monitors()) do connected[m.name] = true end"]
    sources = [o for o in outputs if o["enabled"] and not o["mirror"]]
    for output in ordered(outputs):
        # Never persistently disable a fallback output unless a saved independent
        # display is actually present. Startup enumeration may be empty: fail open.
        if not output["enabled"]:
            condition = " or ".join("connected[" + lua_string(o["name"]) + "]" for o in sources) or "false"
            lines.append("if " + condition + " then " + rule(output) + " end")
        elif output["mirror"]:
            lines.append("if connected[" + lua_string(output["mirror"]) + "] then " + rule(output) + " end")
        else:
            lines.append(rule(output))
    return "\n".join(lines) + "\n"


def inspect():
    state, run = locations()
    outputs = discover()
    status = read_json(run / "status.json", {"state": "idle"})
    status["remaining"] = max(0, math.ceil(status.get("deadline", 0) - time.monotonic()))
    return {"outputs": outputs, "fingerprint": fingerprint(outputs), "transaction": status,
            "persistent": managed(),
            "saved": (state / "confirmed.lua").exists()}


def managed():
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "k4/monitors.json"
    return read_json(config, {}).get("managed", False) is True


def begin(request):
    _, run = locations()
    lock = os.open(run / "lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        live = discover()
        if request.get("fingerprint") != fingerprint(live):
            raise ValueError("The monitor configuration changed externally. Discard edits and refresh.")
        target = validate(request.get("outputs"), live)
        token = uuid.uuid4().hex
        record = {"token": token, "before": editable(live), "target": target,
                  "state": "starting", "session": os.environ["HYPRLAND_INSTANCE_SIGNATURE"]}
        atomic(run / "status.json", json.dumps(record))
        try:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "worker", str(lock)],
                             pass_fds=(lock,), start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            record.update(state="failed", error="Could not start the monitor recovery worker.")
            atomic(run / "status.json", json.dumps(record))
            raise
        return {"token": token}
    except BlockingIOError as exc:
        raise ValueError("Another monitor preview is already active.") from exc
    finally:
        os.close(lock)


def recover(before):
    live = discover()
    connected = {o["name"] for o in live}
    restore = [o.copy() for o in before if o["name"] in connected]
    for output in restore:
        if output["mirror"] not in connected:
            output["mirror"] = ""
    if not any(o["enabled"] and not o["mirror"] for o in restore):
        if not live:
            raise RuntimeError("No connected output is available for recovery.")
        fallback = next((o for o in restore if o["name"].startswith("eDP")), None)
        if fallback is None:
            fallback = editable(live)[0]
            restore = [o for o in restore if o["name"] != fallback["name"]] + [fallback]
        fallback.update(enabled=True, mirror="", mode="preferred", scale=1, transform=0, x=0, y=0)
    apply(restore)
    # New outputs keep their existing configuration; verify the restored subset.
    expected = restore + [o for o in editable(live) if o["name"] not in {r["name"] for r in restore}]
    verify(expected)


def worker(lock):
    state, run = locations()
    record = read_json(run / "status.json")
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    def interrupted(_signum, _frame):
        raise RuntimeError("Monitor preview interrupted.")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    def publish(stage, error=""):
        record.update(state=stage, error=error)
        atomic(run / "status.json", json.dumps(record))
    committed = False
    server = socket.socket(socket.AF_UNIX)
    address = run / "control.sock"
    try:
        address.unlink(missing_ok=True)
        server.bind(str(address))
        os.chmod(address, 0o600)
        server.listen(2)
        server.settimeout(0.25)
        publish("applying")
        apply(record["target"])
        verify(record["target"])
        record["deadline"] = time.monotonic() + TIMEOUT
        publish("testing")
        while time.monotonic() < record["deadline"]:
            # Hotplug, a reload or another writer invalidates confirmation.
            if not matches(record["target"], discover()):
                raise RuntimeError("The monitor configuration changed during the preview.")
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            with client:
                client.settimeout(1)
                command = json.loads(client.recv(4096))
                if command.get("token") != record["token"]:
                    client.sendall(b'{"error":"Expired monitor transaction."}')
                    continue
                if command.get("action") == "revert":
                    client.sendall(b'{"ok":true}')
                    break
                if command.get("action") != "keep":
                    client.sendall(b'{"error":"Unknown monitor action."}')
                    continue
                if time.monotonic() >= record["deadline"]:
                    break
                verify(record["target"], 1)
                if time.monotonic() >= record["deadline"]:
                    break
                publish("saving")
                if managed():
                    destination = state / "confirmed.lua"
                    previous = destination.read_text() if destination.exists() else None
                    try:
                        atomic(destination, confirmed_lua(record["target"]))
                    except OSError:
                        # A directory fsync can fail after rename. Restore the old
                        # persistent state as well as rolling back the live preview.
                        if previous is None:
                            destination.unlink(missing_ok=True)
                        else:
                            atomic(destination, previous)
                        raise
                committed = True
                publish("kept")
                try:
                    client.sendall(b'{"ok":true}')
                except BrokenPipeError:
                    pass
                return
    except Exception as exc:
        record["error"] = str(exc)
    finally:
        if not committed:
            error = record.get("error", "")
            try:
                publish("reverting", error)
                recover(record["before"])
                publish("reverted", error)
            except Exception as exc:
                publish("failed", error + " Recovery: " + str(exc))
        server.close()
        address.unlink(missing_ok=True)
        os.close(lock)


def decide(action, token):
    _, run = locations()
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(7)
        client.connect(str(run / "control.sock"))
        client.sendall(json.dumps({"action": action, "token": token}).encode())
        return json.loads(client.recv(4096))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "begin", "keep", "revert", "worker"))
    parser.add_argument("argument", nargs="?")
    args = parser.parse_args()
    try:
        if args.action == "worker":
            worker(int(args.argument))
            return 0
        if args.action == "inspect":
            result = inspect()
        elif args.action == "begin":
            result = begin(json.loads(sys.stdin.readline()))
        else:
            result = decide(args.action, args.argument)
        print(json.dumps(result))
        return 1 if "error" in result else 0
    except Exception as exc:
        print(json.dumps({"error": str(exc)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
