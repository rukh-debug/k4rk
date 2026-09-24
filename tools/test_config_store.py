#!/usr/bin/env python3
"""Settings-only exports, private storage, migration and cross-file recovery."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import config_store as store
import migrate_config as migration
import config_outputs
import credentials


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        env = {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / "config"),
               "XDG_STATE_HOME": str(self.home / "state"), "XDG_CACHE_HOME": str(self.home / "cache"),
               "XDG_RUNTIME_DIR": str(self.home / "run")}
        self.env = patch.dict(os.environ, env)
        self.env.start()
        self.addCleanup(self.env.stop)

    def write_v1(self, **sections):
        data = dict(schemaVersion=1, revision=21, shell={}, features={}, plugins={}, cache={},
                    migration=dict(version=1, imported=[], pendingCredentials=[]))
        data.update(sections)
        store.config_path().parent.mkdir(parents=True, exist_ok=True)
        store.config_path().write_text(json.dumps(data))
        return data

    def test_concurrent_writers_preserve_preferences_and_separate_state(self):
        children = []
        for number in range(12):
            ident = "test-" + str(number)
            operations = [dict(path=["plugins", ident, "settings"], value={"size": number}),
                          dict(path=["plugins", ident, "state"], value={"score": number})]
            child = subprocess.Popen([sys.executable, "-B", store.__file__, "transact"],
                                     stdin=subprocess.PIPE, stdout=subprocess.DEVNULL)
            child.stdin.write(json.dumps(dict(operations=operations)).encode())
            child.stdin.close()
            children.append(child)
        for child in children:
            self.assertEqual(child.wait(timeout=10), 0)
        data = store.read()
        self.assertEqual(len(data["plugins"]), 12)
        self.assertNotIn("revision", data)
        for number in range(12):
            ident = "test-" + str(number)
            self.assertEqual(set(data["plugins"][ident]), {"settings"})
            self.assertEqual(store.get(["plugins", ident, "state", "score"]), number)
        self.assertEqual(store.config_path().stat().st_mode & 0o777, 0o600)
        self.assertFalse(store.journal_path().exists())

    def test_digest_conflicts_preserve_explicit_false_zero_and_empty_values(self):
        store.put(["shell", "uiSoundsEnabled"], False)
        version = store.etag(store.read())
        store.transaction([dict(path=["shell", "barAlignment"], value=0),
                           dict(path=["shell", "quickAccess"], value=[])], version)
        with self.assertRaisesRegex(ValueError, "changed"):
            store.transaction([dict(path=["shell", "uiSoundsEnabled"], value=True)], version)
        self.assertEqual(store.get(["shell"]), dict(uiSoundsEnabled=False, barAlignment=0, quickAccess=[]))

    def test_state_and_cache_do_not_touch_config_bytes_or_mtime(self):
        store.initialize()
        before = store.config_path().read_bytes(), store.config_path().stat().st_mtime_ns
        store.put(["cache", "agents", "quota"], {"usage": 60})
        store.put(["cache", "pluginCatalog"], {"plugins": []})
        store.put(["plugins", "openwebui", "state"], {"messages": [{"content": "private conversation"}]})
        store.put(["features", "wallpaper", "source"], "/private/wallpaper.png")
        self.assertEqual(before, (store.config_path().read_bytes(), store.config_path().stat().st_mtime_ns))
        self.assertTrue((store.cache_root() / "agents/quota.json").exists())
        self.assertTrue((store.cache_root() / "plugins/catalog.json").exists())
        self.assertTrue((store.state_root() / "plugins/openwebui/state.json").exists())
        self.assertNotIn("private", store.encode(store.read()))

    def test_invalid_shared_file_is_never_overwritten(self):
        store.config_path().parent.mkdir(parents=True)
        for text in ("{broken", json.dumps(dict(store.empty(), schemaVersion=999)), "[]"):
            store.config_path().write_text(text)
            with self.assertRaises(ValueError):
                store.put(["shell", "barAlignment"], 10)
            self.assertEqual(store.config_path().read_text(), text)

    def test_shared_schema_rejects_state_and_personal_profiles(self):
        for root in ("cache", "retired", "migration", "revision"):
            data = dict(store.empty(), **{root: {}})
            with self.assertRaises(ValueError): store.validate(data)
        for plugin in ({"state": {}}, {"installation": {}}, {"hosts": {}}):
            data = store.empty(); data["plugins"]["ssh"] = plugin
            with self.assertRaises(ValueError): store.validate(data)
        for path, value in ((["plugins", "openwebui", "settings", "baseUrl"], "https://private.example"),
                            (["shell", "pillMigrated"], True)):
            with self.assertRaises(ValueError): store.put(path, value)

    def test_credentials_are_rejected_in_all_domains(self):
        for path in (["plugins", "example", "settings"], ["plugins", "example", "state"], ["cache", "agents", "quota"]):
            for key in ("password", "apiToken", "private_key", "refreshToken", "token"):
                with self.subTest(path=path, key=key), self.assertRaisesRegex(ValueError, "keyring"):
                    store.put(path, {"nested": [{key: "secret"}]})

    def test_migration_splits_preferences_profiles_history_and_metadata(self):
        manifest = store.plugin_root() / "external/plugin.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('{"id":"external"}')
        self.write_v1(
            shell={"barAlignment": 0, "uiSoundsEnabled": False, "pillMigrated": True,
                   "nightLightLocation": {"latitude": 1}, "nightLightOverride": {"until": 123},
                   "quickAccess": ["game", "system", "dual", "terminal", "agents", "digivice", "settings", "weather"],
                   "islandPlacements": {"dual": {}, "terminal": {"side": "top", "align": 50}}},
            features={"wallpaper": {"source": "/private/background", "extras": ["/private/photos"], "scheme": "vibrant"},
                      "monitors": {"outputs": [{"name": "private-monitor"}]}},
            plugins={"agents": {"enabled": False, "state": {"threshold": 0, "providers": []}},
                     "system": {"state": {"chipCpu": False}}, "dual": {"state": {"dock": True}},
                     "digivice": {"partida": {}}, "hyprtheme": {"enabled": False}, "player": {"enabled": True},
                     "openwebui": {"settings": {"baseUrl": "https://private.example", "draftEmail": "private@example",
                                                "currentModel": "private-model", "rememberHistory": True},
                                   "state": {"messages": ["private chat"]}},
                     "ssh": {"hosts": {"private-host": {"user": "personal"}}},
                     "external": {"settings": {"compact": True}, "installation": {"repo": "https://example.org/plugin"}}},
            cache={"pluginCatalog": {"plugins": []}, "agents": {"quota": {"usage": 10}}},
            retired={"savedGame": {"gold": 20}, "weather": {"place": "private place"}})
        report = migration.migrate()
        data = store.read()
        self.assertEqual(set(data), {"schemaVersion", "shell", "features", "plugins"})
        self.assertEqual(data["shell"]["quickAccess"], ["system", "terminal", "agents", "settings"])
        self.assertNotIn("dual", data["shell"]["islandPlacements"])
        self.assertEqual(data["plugins"]["agents"], {"enabled": False, "settings": {"threshold": 0, "providers": []}})
        self.assertEqual(data["plugins"]["system"]["settings"], {"chipCpu": False})
        self.assertEqual(data["plugins"]["openwebui"]["settings"], {"rememberHistory": True})
        self.assertEqual(set(report["removedPlugins"]), {"dual", "digivice", "hyprtheme"})
        self.assertNotIn("private", store.encode(data))
        self.assertEqual(store.get(["plugins", "openwebui", "state", "messages"]), ["private chat"])
        self.assertEqual(store.get(["plugins", "openwebui", "profile", "draftEmail"]), "private@example")
        self.assertEqual(store.get(["shell", "nightLightLocation"]), {"latitude": 1})
        self.assertTrue((store.plugin_root() / "external/.installation.json").exists())
        self.assertTrue(migration.report_path(1).exists())
        self.assertFalse(store.journal_path().exists())

    def test_old_installation_metadata_does_not_recreate_uninstalled_plugins(self):
        self.write_v1(plugins={"missing": {"installation": {"repo": "https://example.org/plugin"}}})
        migration.migrate()
        self.assertFalse((store.plugin_root() / "missing").exists())
        self.assertNotIn("missing", store.read()["plugins"])
        self.assertTrue((store.state_root() / "retired/installations.json").exists())

    def test_installed_replacement_or_temporarily_broken_plugin_is_preserved(self):
        (store.plugin_root() / "dual").mkdir(parents=True)
        self.write_v1(plugins={"dual": {"enabled": False, "settings": {"compact": True}}})
        migration.migrate()
        self.assertEqual(store.read()["plugins"]["dual"], {"enabled": False, "settings": {"compact": True}})

    def test_destination_conflicts_preserve_newer_local_data(self):
        target = store.state_root() / "plugins/openwebui/state.json"
        store.atomic_write(target, '{"messages":["newer"]}')
        self.write_v1(plugins={"openwebui": {"state": {"messages": ["older"]}}})
        report = migration.migrate()
        self.assertEqual(store.get(["plugins", "openwebui", "state", "messages"]), ["newer"])
        self.assertEqual(len(report["conflicts"]), 1)
        self.assertNotIn("older", store.config_path().read_text())

    def test_profile_conflict_cannot_attach_another_servers_history(self):
        profile = store.state_root() / "plugins/openwebui/profile.json"
        store.atomic_write(profile, '{"baseUrl":"https://new.example"}')
        self.write_v1(plugins={"openwebui": {"settings": {"baseUrl": "https://old.example"},
                                            "state": {"messages": ["older account"]}}})
        report = migration.migrate()
        self.assertEqual(store.get(["plugins", "openwebui", "profile", "baseUrl"]), "https://new.example")
        self.assertFalse((store.state_root() / "plugins/openwebui/state.json").exists())
        self.assertEqual(len(report["conflicts"]), 2)

    def test_reset_and_missing_report_cannot_resurrect_old_values(self):
        self.write_v1(shell={"barAlignment": 12}, plugins={"dual": {"enabled": True}})
        migration.migrate()
        migration.report_path().unlink()
        store.put(["shell", "barAlignment"], 70)
        migration.migrate()
        self.assertEqual(store.get(["shell", "barAlignment"]), 70)
        legacy = store.state_root() / "ajustes.json"
        store.atomic_write(legacy, '{"barAlignment":12}')
        store.config_path().unlink()
        store.initialize()
        self.assertEqual(store.get(["shell", "barAlignment"]), 50)
        self.assertNotIn("dual", store.read()["plugins"])

    def test_corrupt_migration_report_is_not_a_runtime_dependency(self):
        store.initialize()
        store.atomic_write(migration.report_path(), "broken")
        store.initialize()
        self.assertEqual(store.read()["schemaVersion"], 2)

    def test_local_files_cannot_shadow_shared_preferences(self):
        store.initialize()
        store.atomic_write(store.state_root() / "plugins/example/settings.json", '{"compact":false}')
        store.atomic_write(store.state_root() / "shell.json", '{"barAlignment":12,"nightLightLocation":{}}')
        store.atomic_write(store.state_root() / "wallpaper.json", '{"scheme":"old","source":"/private/image"}')
        local = store.snapshot()["local"]
        self.assertNotIn("example", local.get("plugins", {}))
        self.assertNotIn("barAlignment", local["shell"])
        self.assertNotIn("scheme", local["features"]["wallpaper"])

    def test_interrupted_multi_file_commit_recovers_before_read(self):
        store.put(["plugins", "openwebui", "settings"], {"rememberHistory": True})
        store.put(["plugins", "openwebui", "state"], {"messages": ["old"]})
        script = '''import os,sys
sys.path.insert(0, sys.argv[1])
import config_store as s
original = s.atomic_write
def interrupted(path, text):
    original(path, text)
    if path.name == "state.json": os._exit(23)
s.atomic_write = interrupted
s.put(["plugins","openwebui","settings","rememberHistory"], False)
'''
        result = subprocess.run([sys.executable, "-B", "-c", script, str(Path(store.__file__).parent)])
        self.assertEqual(result.returncode, 23)
        self.assertTrue(store.journal_path().exists())
        self.assertIs(store.get(["plugins", "openwebui", "settings", "rememberHistory"]), False)
        self.assertEqual(store.get(["plugins", "openwebui", "state"]), {})
        self.assertFalse(store.journal_path().exists())

    def test_interrupted_migration_rolls_forward_without_reimport(self):
        self.write_v1(shell={"barAlignment": 0}, plugins={"openwebui": {"state": {"messages": ["chat"]}}})
        script = '''import os,sys
sys.path.insert(0,sys.argv[1])
import config_store as s, migrate_config as m
original = s.atomic_write
def interrupted(path,text):
    original(path,text)
    if path.name == "state.json": os._exit(24)
s.atomic_write = interrupted
m.migrate()
'''
        result = subprocess.run([sys.executable, "-B", "-c", script, str(Path(store.__file__).parent)])
        self.assertEqual(result.returncode, 24)
        store.initialize()
        self.assertEqual(store.get(["shell", "barAlignment"]), 0)
        self.assertEqual(store.get(["plugins", "openwebui", "state", "messages"]), ["chat"])
        self.assertFalse(store.journal_path().exists())

    def test_caught_cross_file_failure_rolls_back_both_documents(self):
        store.put(["shell", "barAlignment"], 30)
        store.put(["plugins", "example", "state"], {"score": 1})
        original = store.atomic_write
        def fail(path, text):
            original(path, text)
            if path == store.config_path() and '"barAlignment": 40' in text:
                raise OSError("directory fsync failed")
        with patch("config_store.atomic_write", side_effect=fail), self.assertRaises(OSError):
            store.transaction([dict(path=["shell", "barAlignment"], value=40),
                               dict(path=["plugins", "example", "state"], value={"score": 2})])
        self.assertEqual(store.get(["shell", "barAlignment"]), 30)
        self.assertEqual(store.get(["plugins", "example", "state", "score"]), 1)

    def test_disabling_history_clears_private_state_for_external_edits_too(self):
        store.put(["plugins", "openwebui", "state"], {"messages": ["private"]})
        data = store.empty()
        data["plugins"]["openwebui"] = {"settings": {"rememberHistory": False}}
        store.atomic_write(store.config_path(), store.encode(data))
        snapshot = store.snapshot()
        self.assertEqual(snapshot["local"]["plugins"]["openwebui"]["state"], {})

    def test_bad_local_state_does_not_break_shareable_settings(self):
        store.initialize()
        store.atomic_write(store.state_root() / "plugins/openwebui/state.json", "broken")
        result = store.snapshot()
        self.assertIn("plugins/openwebui/state", result["localErrors"])
        store.put(["shell", "uiSoundsEnabled"], False)
        self.assertIs(store.read()["shell"]["uiSoundsEnabled"], False)

    def test_corrupt_cache_can_be_rebuilt_without_touching_settings(self):
        store.initialize()
        before = store.config_path().read_bytes()
        path = store.cache_root() / "agents/quota.json"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"\xffbroken")
        self.assertEqual(store.get(["cache", "agents", "quota"], {}), {})
        store.put(["cache", "agents", "quota"], {"usage": 10})
        self.assertEqual(store.read_file(path), {"usage": 10})
        self.assertEqual(store.config_path().read_bytes(), before)

    def test_uninstall_cleans_settings_and_references_but_retains_state(self):
        store.put(["plugins", "example", "settings"], {"compact": True})
        store.put(["plugins", "other", "settings"], {"compact": False})
        store.put(["plugins", "example", "state"], {"score": 4})
        store.put(["shell", "quickAccess"], ["example", "settings"])
        store.put(["shell", "panelOrder"], ["toggles", "example.card", "other.card"])
        store.put(["shell", "islandPlacements"], {"example": {"side": "top"}})
        store.put(["cache", "pluginCatalog"], {"plugins": [{"id": "example"}, {"id": "other"}]})
        store.remove_plugin_settings("example")
        self.assertNotIn("example", store.read()["plugins"])
        self.assertEqual(store.get(["shell", "quickAccess"]), ["settings"])
        self.assertEqual(store.get(["shell", "panelOrder"]), ["toggles", "other.card"])
        self.assertEqual(store.get(["shell", "islandPlacements"]), {})
        self.assertEqual(store.get(["plugins", "example", "state", "score"]), 4)
        self.assertEqual(store.get(["cache", "pluginCatalog", "plugins"]), [{"id": "other"}])

    def test_dry_run_has_no_writes_or_keyring_access(self):
        self.write_v1(plugins={"openwebui": {"settings": {"baseUrl": "https://private.example"}}})
        before = store.config_path().read_bytes()
        with patch("credentials.request", side_effect=AssertionError("keyring accessed")):
            migration.migrate(dry_run=True)
        self.assertEqual(store.config_path().read_bytes(), before)
        self.assertFalse(store.state_root().exists())

    def test_clipboard_is_untouched(self):
        path = store.state_root() / "portapapeles/indice.json"
        store.atomic_write(path, '{"entries":["clipboard text"]}')
        self.write_v1()
        migration.migrate()
        self.assertEqual(path.read_text(), '{"entries":["clipboard text"]}')
        self.assertNotIn("clipboard text", store.encode(store.read()))

    def test_native_outputs_read_the_correct_storage_domains(self):
        store.put(["plugins", "terminal", "settings"], {"size": "15", "trail": "yes"})
        config_outputs.terminal()
        self.assertIn("tamaño = 15", (self.home / "config/k4term/k4term.conf").read_text())
        store.put(["plugins", "ssh", "hosts"], {"private": {"host": "example.invalid", "user": "tester"}})
        config_outputs.ssh()
        self.assertIn("Host private", (self.home / ".ssh/k4.conf").read_text())
        self.assertNotIn("example.invalid", store.encode(store.read()))

    def test_keyring_secret_uses_stdin(self):
        completed = subprocess.CompletedProcess([], 0, "", "")
        with patch("credentials.subprocess.run", return_value=completed) as run:
            credentials.request("set", "ssh", "example", "secret-value")
        self.assertNotIn("secret-value", str(run.call_args.args))
        self.assertEqual(run.call_args.kwargs["input"], "secret-value")


if __name__ == "__main__":
    unittest.main()
