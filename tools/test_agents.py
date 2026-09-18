#!/usr/bin/env python3
"""Usage and catalog regressions with isolated homes and synthetic accounts."""

import contextlib
import io
import json
import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

import agents
import agents_catalog as catalog


GO = {"usage": {
    "rolling": {"percent": 0.5, "resetsAt": "2026-09-16T15:00:00Z"},
    "weekly": {"percent": 80, "resetsAt": "2026-09-20T00:00:00Z"},
    "monthly": {"percent": 21, "resetsAt": "2026-10-01T00:00:00Z"},
}}
ZAI = {"success": True, "data": {"limits": [
    {"type": "TOKENS_LIMIT", "percentage": 0.5, "nextResetTime": 1_789_570_800_000},
    {"type": "TIME_LIMIT", "currentValue": 100, "usage": 1000},
]}}


class IsolatedTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"HOME": str(self.home), "XDG_CACHE_HOME": str(self.home / "cache"),
                                          "XDG_DATA_HOME": str(self.home / "data")}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)


class ProviderTests(IsolatedTest):
    def test_empty_selection_does_no_work(self):
        with patch("agents.shutil.which", side_effect=AssertionError("binary probe")), \
                patch("agents.read_json", side_effect=AssertionError("file read")), \
                patch("agents.request_json", side_effect=AssertionError("HTTP request")):
            self.assertEqual(agents.mira(providers=[]), {"agentes": []})

    def test_default_selection_and_duplicate_removal(self):
        with patch("agents.shutil.which", return_value=None):
            self.assertEqual([row["id"] for row in agents.mira()["agentes"]], ["claude", "codex"])
            self.assertEqual(len(agents.mira(providers=["claude", "claude"])["agentes"]), 1)

    def test_unknown_selection_is_rejected_before_discovery(self):
        with patch("agents.shutil.which", side_effect=AssertionError("probe")):
            with self.assertRaises(ValueError):
                agents.mira(providers=["claude", "unsupported"])

    def test_explicit_empty_cli_and_unknown_flag(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            agents.main(["--providers", ""])
        self.assertEqual(json.loads(output.getvalue()), {"agentes": []})
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            agents.main(["--unexpected"])
        self.assertEqual(error.exception.code, 2)

    def test_http_offline_skips_auth_and_network(self):
        with patch("agents.opencode_key", side_effect=AssertionError("credential read")), \
                patch("agents.zai_key", side_effect=AssertionError("credential read")), \
                patch("agents.request_json", side_effect=AssertionError("HTTP request")):
            rows = agents.mira(False, ["opencode-go", "zai-coding-plan", "zhipuai-coding-plan"])["agentes"]
        self.assertTrue(all(row["status"] == "offline" and not row["limites"] for row in rows))

    def test_opencode_auth_precedence_and_single_card(self):
        auth = self.home / "data/opencode/auth.json"
        catalog.atomic_json(auth, {"opencode": {"type": "api", "key": "zen-key"},
                                   "opencode-go": {"type": "api", "key": "go-key"}})
        self.assertEqual(agents.opencode_key(), "go-key")
        os.environ["ZEN_API_KEY"] = "alias-key"
        self.assertEqual(agents.opencode_key(), "alias-key")
        os.environ["OPENCODE_API_KEY"] = "env-key"
        self.assertEqual(agents.opencode_key(), "env-key")
        with patch("agents.request_json", return_value=GO):
            rows = agents.mira(providers=["opencode-go", "opencode-go"])["agentes"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]["limites"]), 3)
        self.assertNotIn("env-key", json.dumps(rows))

    def test_opencode_ignores_non_api_auth(self):
        catalog.atomic_json(self.home / "data/opencode/auth.json",
                            {"opencode": {"type": "oauth", "key": "not-an-api-key"}})
        self.assertIsNone(agents.opencode_key())

    def test_region_keys_never_cross(self):
        os.environ.update(ZAI_API_KEY="global-key", ZHIPUAI_API_KEY="china-key")
        with patch("agents.query_http", return_value={"limites": []}) as query:
            agents.mira(providers=["zai-coding-plan", "zhipuai-coding-plan"])
        self.assertEqual(query.call_args_list[0].args[1:3],
                         ("global-key", "https://api.z.ai/api/monitor/usage/quota/limit"))
        self.assertEqual(query.call_args_list[1].args[1:3],
                         ("china-key", "https://open.bigmodel.cn/api/monitor/usage/quota/limit"))

    def test_shared_region_alias_requires_unambiguous_selection(self):
        os.environ["ZHIPU_API_KEY"] = "ambiguous-key"
        self.assertEqual(agents.zai_key("global", ["zai-coding-plan"]), "ambiguous-key")
        self.assertIsNone(agents.zai_key("global", ["zai-coding-plan", "zhipuai-coding-plan"]))

    def test_normalization_preserves_small_percentages_and_reset_units(self):
        go = agents.parse_go(GO)["limites"]
        self.assertEqual(go[0]["pct"], 0.5)
        self.assertEqual(go[0]["reinicia"], agents.epoca("2026-09-16T15:00:00Z"))
        zai = agents.parse_zai(ZAI)["limites"]
        self.assertEqual(zai[0]["pct"], 0.5)
        self.assertEqual(zai[0]["reinicia"], 1_789_570_800)
        self.assertTrue(zai[0]["resetEstimated"])
        self.assertEqual(zai[1]["pct"], 10)

    def test_missing_reset_is_not_fabricated(self):
        result = agents.parse_zai({"data": {"limits": [{"type": "TOKENS_LIMIT", "percentage": 42}]}})
        self.assertIsNone(result["limites"][0]["reinicia"])

    def test_invalid_percentages_do_not_become_zero(self):
        for value in (None, True, "bad", float("nan"), float("inf")):
            self.assertIsNone(agents.percentage(value))
        with self.assertRaises(ValueError):
            agents.parse_go({"usage": {"rolling": {"percent": None}}})
        self.assertEqual(agents.parse_zai({"success": False})["status"], "unavailable")

    def test_cache_ttl_and_account_partition(self):
        with patch("agents.request_json", return_value=GO) as request, patch("agents.time.time", return_value=1000):
            first = agents.query_http("opencode-go", "key-a", "https://opencode.ai/usage", agents.parse_go)
            self.assertEqual(agents.query_http("opencode-go", "key-a", "https://opencode.ai/usage", agents.parse_go), first)
            self.assertEqual(request.call_count, 1)
            agents.query_http("opencode-go", "key-b", "https://opencode.ai/usage", agents.parse_go)
            self.assertEqual(request.call_count, 2)
        saved = (catalog.cache_directory() / "opencode-go-usage.json").read_text()
        self.assertNotIn("key-b", saved)
        with patch("agents.request_json", return_value=GO) as request, patch("agents.time.time", return_value=1061):
            agents.query_http("opencode-go", "key-b", "https://opencode.ai/usage", agents.parse_go)
            request.assert_called_once()

    def test_http_failures_are_safe_and_back_off(self):
        for code, status in ((401, "auth"), (403, "auth"), (429, "limited"), (500, "error")):
            with self.subTest(code=code), patch("agents.request_json", side_effect=urllib.error.HTTPError(
                    "https://private/secret", code, "secret response", {}, None)) as request:
                result = agents.query_http("opencode-go", str(code), "https://opencode.ai/usage", agents.parse_go)
                agents.query_http("opencode-go", str(code), "https://opencode.ai/usage", agents.parse_go)
                self.assertEqual(result["status"], status)
                self.assertNotIn("secret", json.dumps(result))
                request.assert_called_once()

    def test_cache_write_failure_does_not_hide_usage(self):
        with patch("agents.request_json", return_value=GO), patch("agents.atomic_json", side_effect=OSError):
            self.assertEqual(agents.query_http("opencode-go", "key", "https://opencode.ai/usage", agents.parse_go)["status"], "ok")

    def test_failed_provider_does_not_hide_next(self):
        os.environ.update(OPENCODE_API_KEY="key", ZAI_API_KEY="key")
        with patch("agents.request_json", side_effect=[ValueError("secret"), ZAI]):
            rows = agents.mira(providers=["opencode-go", "zai-coding-plan"])["agentes"]
        self.assertEqual(rows[0]["status"], "error")
        self.assertEqual(rows[1]["status"], "ok")

    def test_claude_offline_keeps_local_cache(self):
        path = self.home / "claude.json"
        catalog.atomic_json(path, {"cachedUsageUtilization": {"fetchedAtMs": 1000000, "utilization": {
            "limits": [{"kind": "session", "percent": 20, "is_active": True}]}}})
        with patch.object(agents, "CLAUDE_JSONS", [str(path)]), \
                patch("agents.uso_en_vivo", side_effect=AssertionError("network")):
            result = agents.lee_claude(False)
        self.assertEqual(result["limites"][0]["pct"], 20)
        self.assertEqual(result["fuente"], "cache")

    def test_expired_claude_token_is_not_refreshed(self):
        path = self.home / "credentials.json"
        catalog.atomic_json(path, {"claudeAiOauth": {"accessToken": "expired", "expiresAt": 1}})
        with patch.object(agents, "CLAUDE_CREDENCIALES", [str(path)]):
            self.assertIsNone(agents.token_claude())
        self.assertEqual(json.loads(path.read_text())["claudeAiOauth"]["accessToken"], "expired")

    def test_codex_reads_recent_valid_tail_after_empty_session(self):
        sessions = self.home / "sessions"
        sessions.mkdir()
        old = sessions / "rollout-old.jsonl"
        old.write_text("x" * (agents.CODEX_COLA + 10) + "\n" + json.dumps({
            "timestamp": "2026-09-16T12:00:00Z", "payload": {"rate_limits": {
                "primary": {"window_minutes": 300, "used_percent": 12}, "secondary": None}}}) + "\n")
        (sessions / "rollout-new.jsonl").write_text("{}\n")
        with patch.object(agents, "CODEX_SESIONES", [str(sessions)]):
            result = agents.read_codex_rollout()
        self.assertEqual(len(result["limites"]), 1)
        self.assertEqual(result["limites"][0]["pct"], 12)

    def test_codex_explicit_empty_limits_are_not_stale_usage(self):
        sessions = self.home / "sessions"
        sessions.mkdir()
        (sessions / "rollout-new.jsonl").write_text(json.dumps({
            "timestamp": "2026-09-16T12:00:00Z", "payload": {"rate_limits": {
                "limit_id": "premium", "primary": None, "secondary": None}}}) + "\n")
        with patch.object(agents, "CODEX_SESIONES", [str(sessions)]):
            result = agents.read_codex_rollout()
        self.assertEqual(result["status"], "unavailable")
        self.assertIn("without quota windows", result["razon"])

    def test_codex_month_window_is_not_weekly(self):
        window = agents.ventana({"windowDurationMins": 43200, "usedPercent": 25,
                                 "resetsAt": 123}, "primary")
        self.assertEqual(window["nombre"], "30 days")
        self.assertEqual(window["reinicia"], 123)

    def test_codex_offline_never_starts_app_server(self):
        with patch("agents.codex_app_server", side_effect=AssertionError("live query")), \
                patch("agents.read_codex_rollout", return_value={"limites": [], "status": "unavailable"}):
            result = agents.read_codex(False)
        self.assertEqual(result["status"], "unavailable")

    def test_codex_live_failure_falls_back_to_rollout(self):
        cached = {"limites": [{"pct": 17}], "fuente": "cache"}
        with patch("agents.codex_app_server", side_effect=OSError), \
                patch("agents.read_codex_rollout", return_value=cached):
            self.assertEqual(agents.read_codex(True), cached)


class CatalogTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.snapshot = self.home / "snapshot.json"
        self.providers = {ident: {"name": ident.title(), "env": ["KEY"], "doc": "https://example.org/docs", "models": {}}
                          for ident in ("anthropic", "opencode", "opencode-go", "new-provider", "zai", "zai-coding-plan")}
        catalog.atomic_json(self.snapshot, {"version": 1, "providers": catalog.normalize(self.providers)})

    def test_catalog_never_discovers_credentials(self):
        with patch("agents.opencode_key", side_effect=AssertionError("credentials")), \
                patch("agents.shutil.which", side_effect=AssertionError("binary probe")):
            rows = agents.provider_catalog(self.snapshot)["providers"]
        self.assertEqual(len(rows), len(self.providers))
        by_id = {row["id"]: row for row in rows}
        self.assertEqual(by_id["anthropic"]["adapter"], "claude")
        self.assertEqual(by_id["opencode"]["adapter"], "")
        self.assertEqual(by_id["opencode-go"]["adapter"], "opencode-go")
        self.assertEqual(by_id["new-provider"]["adapter"], "")
        self.assertEqual(by_id["zai"]["adapter"], "")

    def test_offline_ignores_refresh_and_logo_requests(self):
        with patch("agents_catalog.request_bytes", side_effect=AssertionError("HTTP")):
            result = agents.provider_catalog(self.snapshot, refresh=True, online=False, logo="anthropic")
        self.assertEqual(len(result["providers"]), len(self.providers))

    def test_refresh_and_failure_preserve_complete_cache(self):
        with patch("agents_catalog.request_json", return_value=self.providers):
            self.assertEqual(catalog.load_catalog(self.snapshot, refresh=True)["origin"], "live")
        for failure in (OSError(), ValueError()):
            with patch("agents_catalog.request_json", side_effect=failure):
                result = catalog.load_catalog(self.snapshot, refresh=True)
            self.assertEqual(result["origin"], "cache")
            self.assertEqual(len(result["providers"]), len(self.providers))
            self.assertTrue(result["error"])

    def test_truncated_catalog_does_not_replace_snapshot(self):
        with patch("agents_catalog.request_json", return_value={"anthropic": self.providers["anthropic"]}):
            result = catalog.load_catalog(self.snapshot, refresh=True)
        self.assertEqual(len(result["providers"]), len(self.providers))
        self.assertTrue(result["error"])

    def test_bad_cache_falls_back_to_bundle(self):
        catalog.atomic_json(catalog.cache_directory() / "models-dev-providers.json", {"version": 1, "providers": [{"id": "../escape"}]})
        self.assertEqual(catalog.load_catalog(self.snapshot)["origin"], "bundled")

    def test_invalid_urls_and_paths_never_become_actions(self):
        self.assertEqual(catalog.safe_url("file:///etc/passwd"), "")
        self.assertEqual(catalog.safe_url("https://user:secret@example.org"), "")
        with self.assertRaises(ValueError):
            catalog.normalize({"../escape": {"name": "Unsafe", "env": []}})
        with patch("agents_catalog.request_bytes", side_effect=AssertionError("HTTP")):
            catalog.load_catalog(self.snapshot, logo="../escape")

    def test_catalog_accepts_published_digit_prefixed_env_name(self):
        rows = catalog.normalize({"302ai": {"name": "302.AI", "env": ["302AI_API_KEY"]}})
        self.assertEqual(rows[0]["env"], ["302AI_API_KEY"])

    def test_bundle_contains_every_supported_catalog_identity(self):
        bundled = catalog.valid_snapshot(catalog.read_json(catalog.SNAPSHOT))
        self.assertIsNotNone(bundled)
        ids = {row["id"] for row in bundled["providers"]}
        self.assertGreater(len(ids), 100)
        self.assertTrue({provider["catalog"] for provider in agents.PROVIDERS.values()} <= ids)

    def test_redirects_are_not_followed_with_authentication(self):
        self.assertIsNone(catalog.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.example"))


if __name__ == "__main__":
    unittest.main()
