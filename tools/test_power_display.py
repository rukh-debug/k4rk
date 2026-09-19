"""Behavioral tests for solar boundaries, backend confirmation and power errors."""

import subprocess
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import night_light as night
import power_mode as power

UTC = timezone.utc
CITY = {"latitude": 40.7128, "longitude": -74.006, "timezone": "America/New_York"}


class SolarTests(unittest.TestCase):
    def settings(self, **changes):
        return {"enabled": True, "mode": "solar", "temperature": 4000, "location": CITY, **changes}

    def test_day_night_and_off(self):
        day = datetime(2026, 9, 18, 16, tzinfo=UTC)
        midnight = datetime(2026, 9, 19, 4, tzinfo=UTC)
        self.assertTrue(night.evaluate(self.settings(), day)["identity"])
        self.assertEqual(night.evaluate(self.settings(), midnight)["target"], 4000)
        self.assertTrue(night.evaluate(self.settings(enabled=False), midnight)["identity"])

    def test_fade_is_anchored_to_wall_clock(self):
        now = datetime(2026, 9, 18, 16, tzinfo=UTC)
        boundary = night.solar_schedule(CITY, now)["sunset"]
        values = []
        for offset in (-450, -225, 0, 225, 450):
            values.append(night.evaluate(self.settings(), datetime.fromtimestamp(boundary + offset, UTC))["target"])
        self.assertEqual(values[0], 6500)
        self.assertEqual(values[-1], 4000)
        self.assertEqual(values, sorted(values, reverse=True))
        self.assertAlmostEqual(values[2], 5250, delta=10)

    def test_override_survives_restart_and_expires_after_resume(self):
        now = datetime(2026, 9, 19, 4, tzinfo=UTC)
        end = night.solar_schedule(CITY, now)["nextBoundary"]
        settings = self.settings(override={"active": False, "until": end})
        self.assertTrue(night.evaluate(settings, now)["identity"])
        self.assertTrue(night.evaluate(settings, now + timedelta(hours=1))["overridden"])
        after = night.evaluate(settings, datetime.fromtimestamp(end + 600, UTC))
        self.assertFalse(after["overridden"])
        self.assertTrue(after["identity"])

    def test_dst_and_date_line(self):
        for city in (CITY, {"latitude": -36.85, "longitude": 174.76, "timezone": "Pacific/Auckland"}):
            for now in (datetime(2026, 3, 8, 7, tzinfo=UTC), datetime(2026, 11, 1, 6, tzinfo=UTC)):
                state = night.evaluate(self.settings(location=city), now)
                self.assertGreater(state["nextBoundary"], now.timestamp())
                self.assertLess(state["nextBoundary"] - now.timestamp(), 86400)
                self.assertTrue(4000 <= state["target"] <= 6500)

    def test_polar_day_and_night(self):
        city = {"latitude": 78.22, "longitude": 15.65, "timezone": "Arctic/Longyearbyen"}
        summer = night.evaluate(self.settings(location=city), datetime(2026, 6, 21, 12, tzinfo=UTC))
        winter = night.evaluate(self.settings(location=city), datetime(2026, 12, 21, 12, tzinfo=UTC))
        self.assertTrue(summer["polar"])
        self.assertTrue(summer["identity"])
        self.assertTrue(winter["polar"])
        self.assertEqual(winter["target"], 4000)

    def test_missing_city_and_zero_coordinates(self):
        self.assertTrue(night.evaluate(self.settings(location={}))["needsLocation"])
        self.assertTrue(night.evaluate(self.settings(location={}))["identity"])
        night.evaluate(self.settings(location={"latitude": 0, "longitude": 0, "timezone": "UTC"}))
        with self.assertRaises(ValueError):
            night.evaluate(self.settings(location={**CITY, "latitude": float("nan")}))
        with self.assertRaises(ValueError):
            night.evaluate(self.settings(temperature=20000))


class BackendTests(unittest.TestCase):
    def test_apply_then_confirm(self):
        with patch.object(night, "ipc", side_effect=["true", "6000", "ok", "false", "4000"]) as ipc:
            result = night.reconcile({"enabled": True, "temperature": 4000})
        self.assertTrue(result["available"])
        self.assertEqual(ipc.call_args_list[2].args, ("temperature", 4000))

    def test_off_uses_identity_not_a_guessed_neutral_temperature(self):
        with patch.object(night, "ipc", side_effect=["false", "4000", "ok", "true", "4000"]) as ipc:
            result = night.reconcile({"enabled": False})
        self.assertFalse(result["active"])
        self.assertEqual(ipc.call_args_list[2].args, ("identity",))

    def test_failed_or_unconfirmed_write_is_not_reported_as_active(self):
        for replies in (["true", "6000", "invalid command"], ["true", "6000", "ok", "true", "6000"]):
            with patch.object(night, "ipc", side_effect=replies):
                result = night.reconcile({"enabled": True})
            self.assertFalse(result["available"])
            self.assertIn("error", result)

    def test_backend_restart_reapplies_saved_preference(self):
        with patch.object(night, "ipc", side_effect=RuntimeError("service stopped")):
            self.assertFalse(night.reconcile({"enabled": True})["available"])
        with patch.object(night, "ipc", side_effect=["true", "6000", "ok", "false", "4000"]):
            self.assertTrue(night.reconcile({"enabled": True})["active"])

    def test_no_redundant_temperature_write(self):
        with patch.object(night, "ipc", side_effect=["false", "4000", "false", "4000"]) as ipc:
            night.reconcile({"enabled": True})
        self.assertEqual(ipc.call_count, 4)

    def test_unsupported_power_profile_is_not_written(self):
        with patch.object(power, "inspect", return_value={"profiles": ["balanced", "power-saver"]}), patch.object(power, "run") as run:
            with self.assertRaises(ValueError):
                power.main(["performance"])
            run.assert_not_called()

    def test_power_write_requires_daemon_confirmation(self):
        state = {"profiles": list(power.PROFILES), "profile": "balanced", "available": True}
        with patch.object(power, "inspect", return_value=state), patch.object(power, "run"):
            self.assertIn("error", power.main(["performance"]))

    def test_power_permission_failure(self):
        with patch.object(power.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "Access denied")):
            with self.assertRaisesRegex(RuntimeError, "Access denied"):
                power.run(["powerprofilesctl", "set", "performance"])


if __name__ == "__main__":
    unittest.main()
