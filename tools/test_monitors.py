#!/usr/bin/env python3
"""Monitor contracts and real detached-worker tests against an isolated fake IPC."""
import copy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import monitors as m


RAW = [{"name": "eDP-1", "width": 1920, "height": 1200, "refreshRate": 60.096,
        "x": 0, "y": 0, "scale": 1, "transform": 0, "disabled": False, "mirrorOf": "none",
        "availableModes": ["1920x1200@60.10Hz", "1920x1200@60.10Hz"]},
       {"name": "HDMI-A-1", "width": 1920, "height": 1080, "refreshRate": 60,
        "x": 1920, "y": 0, "scale": 1, "transform": 0, "disabled": False, "mirrorOf": "none",
        "availableModes": ["1920x1080@60.00Hz", "1920x1080@59.94Hz", "1920x1080@74.97Hz"]}]

FAKE = r'''
import json, os, re, sys
from pathlib import Path
path = Path(os.environ["FAKE_MONITORS"])
data = json.loads(path.read_text())
if sys.argv[1:] == ["-j", "monitors", "all"]:
    print(json.dumps(data))
elif sys.argv[1] == "eval":
    for line in sys.argv[2].splitlines():
        name = re.search(r'output = "([^"]+)"', line)[1]
        output = next(o for o in data if o["name"] == name)
        mode = re.search(r'mode = "([^"]+)"', line)[1]
        if mode != "preferred":
            match = re.fullmatch(r'(\d+)x(\d+)@([\d.]+)', mode)
            output.update(width=int(match[1]), height=int(match[2]), refreshRate=float(match[3]))
        pos = re.search(r'position = "(-?\d+)x(-?\d+)"', line)
        output.update(x=int(pos[1]), y=int(pos[2]),
                      scale=float(re.search(r'scale = ([\d.]+)', line)[1]),
                      transform=int(re.search(r'transform = (\d+)', line)[1]),
                      disabled='disabled = true' in line,
                      mirrorOf=re.search(r'mirror = "([^"]*)"', line)[1] or 'none')
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data))
    temp.replace(path)
    print('ok')
else:
    sys.exit(1)
'''


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.live = m.normalize(copy.deepcopy(RAW))
        self.draft = m.editable(self.live)

    def test_modes_are_deduplicated_without_collapsing_refresh_rates(self):
        self.assertEqual(self.live[1]["modes"], ["1920x1200@60.10"])
        self.assertEqual(self.live[1]["mode"], "1920x1200@60.10")
        self.assertEqual(len(self.live[0]["modes"]), 3)

    def test_scale_and_last_output_validation(self):
        self.draft[0]["scale"] = 1.4
        with self.assertRaisesRegex(ValueError, "whole logical pixels"):
            m.validate(self.draft, self.live)
        self.draft[0]["scale"] = 1.5
        m.validate(self.draft, self.live)
        for output in self.draft:
            output["enabled"] = False
        with self.assertRaisesRegex(ValueError, "independent"):
            m.validate(self.draft, self.live)

    def test_stale_topology_and_mirror_cycles(self):
        with self.assertRaises(ValueError):
            m.validate(self.draft[:1], self.live)
        self.draft[0]["mirror"] = self.draft[1]["name"]
        self.draft[1]["mirror"] = self.draft[0]["name"]
        with self.assertRaises(ValueError):
            m.validate(self.draft, self.live)

    def test_lua_reset_fields_and_escaping(self):
        self.draft[0]["name"] = 'output"\n\\é'
        rule = m.rule(self.draft[0])
        self.assertIn('disabled = false', rule)
        self.assertIn('mirror = ""', rule)
        self.assertIn('transform = 0', rule)
        self.assertNotIn('\n', rule)
        self.assertIn('\\034', rule)
        self.assertIn('\\010', rule)

    def test_persistent_disable_requires_a_present_source(self):
        self.draft[1]["enabled"] = False
        text = m.confirmed_lua(self.draft)
        self.assertIn('if connected["HDMI-A-1"] then hl.monitor', text)

    def test_readback_detects_rejected_mode_and_external_changes(self):
        self.assertTrue(m.matches(self.draft, self.live))
        self.live[0]["refreshRate"] = 59.94
        # 60 vs 59.94 is a distinct advertised rate, not a rounded readback.
        self.assertFalse(m.matches(self.draft, self.live))
        self.draft[0]["mode"] = "1920x1080@74.97"
        self.assertFalse(m.matches(self.draft, self.live))


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.fake = self.root / "outputs.json"
        self.fake.write_text(json.dumps(RAW))
        binary = self.root / "hyprctl"
        binary.write_text("#!" + sys.executable + "\n" + FAKE)
        binary.chmod(0o700)
        self.env = {"XDG_RUNTIME_DIR": str(self.root / "run"),
                    "XDG_STATE_HOME": str(self.root / "state"),
                    "XDG_CONFIG_HOME": str(self.root / "config"),
                    "HYPRLAND_INSTANCE_SIGNATURE": "isolated-test-session",
                    "PATH": str(self.root) + os.pathsep + os.environ.get("PATH", ""),
                    "FAKE_MONITORS": str(self.fake)}
        self.patch = patch.dict(os.environ, self.env)
        self.patch.start()
        self.state, self.run = m.locations()
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=10)
        # A detached begin() worker is not our subprocess handle. Wait for recovery.
        until = time.monotonic() + 10
        while time.monotonic() < until:
            record = m.read_json(self.run / "status.json", {})
            if record.get("state") not in m.ACTIVE:
                break
            time.sleep(0.05)
        self.patch.stop()
        self.temp.cleanup()

    def wait_for(self, *states):
        until = time.monotonic() + 10
        while time.monotonic() < until:
            record = m.read_json(self.run / "status.json", {})
            if record.get("state") in states:
                return record
            time.sleep(0.04)
        self.fail("Worker did not reach " + str(states) + ": " + str(record))

    def launch(self, seconds=3, injection="", expected="testing"):
        live = m.discover()
        target = m.editable(live)
        target[0]["mode"] = "1920x1080@74.97"
        record = {"token": "test-token", "state": "starting", "before": m.editable(live), "target": target}
        m.atomic(self.run / "status.json", json.dumps(record))
        lock = os.open(self.run / "lock", os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        code = f"import sys; sys.path.insert(0, {str(Path(m.__file__).parent)!r}); import monitors; monitors.TIMEOUT={seconds};\n{injection}\nmonitors.worker({lock})"
        child = subprocess.Popen([sys.executable, "-B", "-c", code], pass_fds=(lock,), start_new_session=True)
        os.close(lock)
        self.children.append(child)
        return self.wait_for(expected)

    def test_timeout_restores_and_never_persists(self):
        self.launch(0.5)
        self.wait_for("reverted")
        self.assertTrue(m.matches(m.editable(m.normalize(RAW)), m.discover()))
        self.assertFalse((self.state / "confirmed.lua").exists())

    def test_confirm_persists_only_after_keep(self):
        os.environ["K4_MONITORS_MANAGED"] = "1"
        record = self.launch()
        self.assertIsNone(m.config_store.get(["features", "monitors", "outputs"]))
        self.assertTrue(m.decide("keep", record["token"])["ok"])
        self.wait_for("kept")
        self.assertIn("74.97", json.dumps(m.config_store.get(["features", "monitors", "outputs"])))
        self.assertFalse((self.state / "confirmed.lua").exists())

    def test_old_token_and_concurrent_preview_are_rejected(self):
        record = self.launch()
        self.assertIn("error", m.decide("keep", "old-token"))
        with self.assertRaisesRegex(ValueError, "already active"):
            m.begin({})
        m.decide("revert", record["token"])
        self.wait_for("reverted")

    def test_hotplug_restores_remaining_monitor(self):
        self.launch()
        data = json.loads(self.fake.read_text())
        self.fake.write_text(json.dumps([o for o in data if o["name"] == "eDP-1"]))
        self.wait_for("reverted")
        self.assertTrue(m.discover()[0]["enabled"])

    def test_hotplug_reenables_previously_disabled_fallback(self):
        data = copy.deepcopy(RAW)
        data[0]["disabled"] = True
        self.fake.write_text(json.dumps(data))
        self.launch()
        data = json.loads(self.fake.read_text())
        self.fake.write_text(json.dumps([o for o in data if o["name"] == "eDP-1"]))
        self.wait_for("reverted")
        self.assertTrue(m.discover()[0]["enabled"])

    def test_partial_apply_failure_rolls_back_all_outputs(self):
        injection = '''
original_apply = monitors.apply
calls = 0
def partial_apply(outputs):
    global calls
    calls += 1
    if calls == 1:
        original_apply(outputs[:1])
        raise RuntimeError("Simulated partial apply failure")
    return original_apply(outputs)
monitors.apply = partial_apply
'''
        record = self.launch(injection=injection, expected="reverted")
        self.assertIn("partial apply failure", record["error"])
        self.assertTrue(m.matches(m.editable(m.normalize(RAW)), m.discover()))

    def test_begin_worker_survives_request_process_exit(self):
        live = m.discover()
        target = m.editable(live)
        target[0]["x"] += 20
        reply = subprocess.run([sys.executable, "-B", m.__file__, "begin"],
                               input=json.dumps({"outputs": target, "fingerprint": m.fingerprint(live)}) + "\n",
                               text=True, capture_output=True, timeout=5, check=True)
        token = json.loads(reply.stdout)["token"]
        self.wait_for("testing")
        m.decide("revert", token)
        self.wait_for("reverted")
        self.assertTrue(m.matches(m.editable(live), m.discover()))

    def test_interrupted_worker_recovers(self):
        self.launch()
        self.children[-1].terminate()
        self.wait_for("reverted")
        self.assertTrue(m.matches(m.editable(m.normalize(RAW)), m.discover()))

    def test_stale_draft_is_rejected_before_any_write(self):
        with self.assertRaisesRegex(ValueError, "changed externally"):
            m.begin({"outputs": m.editable(m.discover()), "fingerprint": "stale"})
        self.assertFalse((self.run / "status.json").exists())

    def test_failed_persistence_reverts_and_preserves_saved_rules(self):
        os.environ["K4_MONITORS_MANAGED"] = "1"
        previous = m.editable(m.normalize(RAW))
        m.config_store.put(["features", "monitors", "outputs"], previous)
        injection = '''
original_atomic = monitors.config_store.atomic_write
def fail_once(path, text):
    if path.name == "profile.json" and "74.97" in text:
        original_atomic(path, text)
        raise OSError("Simulated directory fsync failure")
    return original_atomic(path, text)
monitors.config_store.atomic_write = fail_once
'''
        record = self.launch(injection=injection)
        try:
            m.decide("keep", record["token"])
        except (ValueError, OSError):
            pass
        self.wait_for("reverted")
        self.assertEqual(m.config_store.get(["features", "monitors", "outputs"]), previous)
        self.assertTrue(m.matches(m.editable(m.normalize(RAW)), m.discover()))


if __name__ == "__main__":
    unittest.main()
