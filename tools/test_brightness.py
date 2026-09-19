"""Brightness protocol, range, permissions and hotplug tests without hardware."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import brightness as b


class BrightnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        for key in ("BACKLIGHT", "DRM", "DEV"):
            path = root / key
            path.mkdir()
            p = patch.object(b, key, path)
            p.start()
            self.addCleanup(p.stop)
        self.backlight = b.BACKLIGHT / "panel"
        self.backlight.mkdir()
        (self.backlight / "brightness").write_text("400")
        (self.backlight / "max_brightness").write_text("800")
        self.connector = b.DRM / "card1-HDMI-A-1"
        self.connector.mkdir()
        (self.connector / "status").write_text("connected")
        edid = bytearray(128)
        edid[54:72] = b"\x00\x00\x00\xfc\x00Test display\n"
        (self.connector / "edid").write_bytes(edid)
        (self.connector / "ddc").symlink_to(root / "i2c-6")
        (b.DEV / "i2c-6").touch()
        p = patch.object(b.shutil, "which", return_value="/bin/mock")
        p.start()
        self.addCleanup(p.stop)

    def test_discovery_and_disconnect(self):
        devices = b.devices()
        self.assertEqual(len(devices), 2)
        self.assertEqual(devices[1]["name"], "Test display · HDMI-A-1")
        self.assertEqual(devices[1]["bus"], 6)
        (self.connector / "status").write_text("disconnected")
        self.assertEqual(len(b.devices()), 1)

    def test_identity_survives_bus_renumbering(self):
        before = b.devices()[1]
        (self.connector / "ddc").unlink()
        (self.connector / "ddc").symlink_to(self.connector.parent / "i2c-9")
        after = b.devices()[1]
        self.assertEqual(before["id"], after["id"])
        self.assertEqual(after["bus"], 9)
        (self.connector / "edid").write_bytes(b"different monitor")
        self.assertNotEqual(after["id"], b.devices()[1]["id"])

    def test_backlight_percentage_and_readback(self):
        device = b.devices()[0]
        self.assertEqual(b.inspect(device)["value"], 50)
        def write(args):
            self.assertEqual(args[:4], ["brightnessctl", "--class=backlight", "--device", "panel"])
            (self.backlight / "brightness").write_text(args[-1])
        with patch.object(b, "run", side_effect=write):
            self.assertEqual(b.set_level(device, 73)["value"], 73)
            self.assertEqual(b.set_level(device, 0)["value"], 1)
            self.assertEqual(b.set_level(device, 110)["value"], 100)

    def test_ddc_non_percent_range_and_confirmation(self):
        device = b.devices()[1]
        with patch.object(b, "run", side_effect=["VCP 10 C 20 255\n", "", "VCP 10 C 128 255\n"]) as run:
            result = b.set_level(device, 50)
        self.assertEqual(run.call_args_list[1].args[0], ["ddcutil", "--bus", "6", "setvcp", "10", "128"])
        self.assertTrue(result["available"])
        self.assertEqual(result["value"], 50)

    def test_bad_ddc_responses(self):
        for output in ("VCP 10 ERR", "VCP 10 SNC x01", "VCP 10 C 10 0", "VCP 10 C 120 100"):
            with self.subTest(output=output), patch.object(b, "run", return_value=output):
                result = b.inspect(b.devices()[1])
                self.assertFalse(result["available"])
                self.assertTrue(result["error"])

    def test_missing_i2c_and_permissions(self):
        device = b.devices()[1]
        with patch.object(b.os, "access", return_value=False):
            self.assertIn("permission", b.inspect(device)["error"])
        (b.DEV / "i2c-6").unlink()
        self.assertIn("hardware.i2c.enable", b.inspect(device)["error"])

    def test_missing_binary(self):
        with patch.object(b.shutil, "which", return_value=None):
            self.assertIn("brightnessctl", b.inspect(b.devices()[0])["error"])

    def test_timeout_and_failure(self):
        with patch.object(b.subprocess, "run", side_effect=subprocess.TimeoutExpired("ddcutil", 6)):
            self.assertIn("did not respond", b.inspect(b.devices()[1])["error"])
        with patch.object(b.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "failure")):
            self.assertIn("command failed", b.inspect(b.devices()[1])["error"])

    def test_invalid_input(self):
        for value in (float("nan"), float("inf")):
            with self.assertRaises(ValueError):
                b.set_level(b.devices()[0], value)


if __name__ == "__main__":
    unittest.main()
