"""Regression checks for hardware and interval process telemetry."""
import os
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

import sistema


class SystemTelemetryTests(unittest.TestCase):
    def test_process_cpu_uses_interval_not_lifetime(self):
        before = {"7": ("worker", 10000, 80, 42)}
        after = {"7": ("worker", 10000 + sistema.RELOJ, 80, 42)}
        self.assertEqual(sistema.top(before, after, 2)[0]["cpu"], 50)

    def test_multithread_cpu_can_exceed_100(self):
        self.assertEqual(sistema.top({"7": ("a", 0, 0, 1)},
                                    {"7": ("a", 4 * sistema.RELOJ, 0, 1)}, 2)[0]["cpu"], 200)

    def test_pid_reuse_and_counter_reset_are_not_activity(self):
        self.assertEqual(sistema.top({"7": ("a", 100, 50, 1)}, {"7": ("b", 900, 50, 2)}, 2), [])
        self.assertEqual(sistema.top({"7": ("a", 100, 50, 1)}, {"7": ("a", 20, 50, 1)}, 2), [])

    def test_invalid_or_suspended_interval(self):
        for dt in (0, -1, 20):
            self.assertEqual(sistema.top({"7": ("a", 0, 50, 1)}, {"7": ("a", 900, 50, 1)}, dt), [])

    def test_memory_leaders_survive_cpu_ranking(self):
        before = {str(i): (str(i), 0, i * 20, i) for i in range(1, 10)}
        after = {str(i): (str(i), 1000 // i, i * 20, i) for i in range(1, 10)}
        self.assertEqual({r["pid"] for r in sistema.top(before, after, 2, 1)}, {1, 9})

    def test_process_stat_parentheses_and_real_page_size(self):
        fields = ["0"] * 22
        fields[11], fields[12], fields[19], fields[21] = "12", "8", "90", "64"
        with patch.object(sistema, "PAGE_SIZE", 65536):
            self.assertEqual(sistema.parse_process("7 (a (worker)) " + " ".join(fields)),
                             ("a (worker)", 20, 4, 90))

    def test_filesystem_preserves_reserved_space(self):
        data = os.statvfs_result((4096, 4096, 1000, 200, 150, 0, 0, 0, 0, 255))
        with patch("sistema.os.statvfs", return_value=data):
            result = sistema.storage("/home/example")
        self.assertEqual(result["used"], 800 * 4096)
        self.assertEqual(result["available"], 150 * 4096)
        self.assertEqual(result["reserved"], 50 * 4096)
        self.assertAlmostEqual(result["percent"], 800 / 950 * 100)

    def test_missing_filesystem(self):
        with patch("sistema.os.statvfs", side_effect=OSError):
            self.assertIsNone(sistema.storage("/missing"))

    def test_filesystem_identity_uses_longest_mount_and_decodes_spaces(self):
        mounts = "1 0 8:1 / / rw - ext4 /dev/root rw\n2 1 8:2 / /home/example\\040data rw - btrfs /dev/data rw"
        identity = sistema.filesystem_identity("/home/example data/files", mounts)
        self.assertEqual(identity["mount"], "/home/example data")
        self.assertEqual(identity["filesystem"], "btrfs")

    def test_missing_sensors(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(sistema.rutas_temperatura(Path(directory)), {"cpu": "", "nvme": ""})

    def test_amd_gpu_available_and_missing_counters(self):
        with tempfile.TemporaryDirectory() as directory:
            device = Path(directory) / "card1/device"
            device.mkdir(parents=True)
            (device / "gpu_busy_percent").write_text("23\n")
            (device / "mem_info_vram_total").write_text("1073741824\n")
            gpu = sistema.discover_gpu(Path(directory))
            reading = sistema.gpu_reading(gpu)
            self.assertEqual(reading["usage"], 23)
            self.assertEqual(reading["total"], 1073741824)
            self.assertIsNone(reading["used"])
            self.assertIsNone(reading["temperature"])
            (device / "gpu_busy_percent").unlink()
            self.assertIsNone(sistema.gpu_reading(gpu)["usage"])

    def test_nvidia_unavailable_value_is_not_zero(self):
        result = type("Result", (), {"returncode": 0, "stdout": "Example GPU, [N/A], 50, 128, 4096\n"})()
        with patch("sistema.subprocess.run", return_value=result):
            reading = sistema.gpu_reading({"provider": "nvidia"})
        self.assertIsNone(reading["usage"])
        self.assertEqual(reading["used"], 128 * 1048576)

    def test_end_process_checks_identity_before_signalling(self):
        with patch("sistema.os.pidfd_open", return_value=8), patch("sistema.os.close"), \
                patch("sistema.Path.read_text", return_value="ignored"), \
                patch("sistema.parse_process", return_value=("worker", 0, 0, 43)), \
                patch("sistema.signal.pidfd_send_signal") as send:
            with self.assertRaises(ProcessLookupError):
                sistema.terminate(7, "42")
            send.assert_not_called()

    def test_terminate_own_fixture_process(self):
        child = subprocess.Popen(["python3", "-c", "import time; time.sleep(30)"])
        try:
            start = sistema.parse_process(Path(f"/proc/{child.pid}/stat").read_text())[3]
            sistema.terminate(child.pid, str(start))
            self.assertEqual(child.wait(timeout=5), -15)
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=5)

    def test_live_filesystem_matches_df(self):
        result = sistema.storage()
        total, used, available = map(int, subprocess.check_output(
            ["df", "-B1", "--output=size,used,avail", str(Path.home())], text=True).splitlines()[1].split())
        self.assertEqual(result["total"], total)
        self.assertLess(abs(result["used"] - used), 64 * 1048576)
        self.assertLess(abs(result["available"] - available), 64 * 1048576)


if __name__ == "__main__":
    unittest.main()
