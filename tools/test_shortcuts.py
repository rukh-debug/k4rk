"""Exercise Lua shortcut parsing and the complete helper output contract."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import shortcuts


class ShortcutParserTests(unittest.TestCase):
    def test_named_sections_dispatchers_and_english_record_fields(self):
        entries = shortcuts.parse_config([
            '-- ── WINDOWS ─────────',
            'hl.bind(mod .. " + Q", hl.dsp.window.close())',
            '-- Media',
            'hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))',
        ], {"mod": "SUPER"})
        self.assertEqual(entries, [
            {"combo": "SUPER + Q", "description": "Close the window",
             "detail": "", "section": "Windows"},
            {"combo": "XF86AudioPlay", "description": "playerctl play-pause",
             "detail": "", "section": "Media"},
        ])

    def test_ipc_prefix_concatenation_excludes_bind_options(self):
        values = {"k4": "quickshell ipc -p /tmp/shell.qml call k4 "}
        entries = shortcuts.parse_config([
            'hl.bind("SUPER + P", hl.dsp.exec_cmd(k4 .. "togglePanel"), { locked = true })',
            'hl.bind("SUPER + D", hl.dsp.exec_cmd("quickshell ipc -p /tmp/shell.qml call k4.apps open"))',
        ], values)
        self.assertEqual([entry["description"] for entry in entries], ["k4 · %1"] * 2)
        self.assertEqual([entry["detail"] for entry in entries], ["togglePanel", "apps open"])

    def test_loop_aliases_show_a_range_and_reset_after_end(self):
        entries = shortcuts.parse_config([
            'for i = 1, COUNT do',
            '    local key = i % 10',
            '    hl.bind(mod .. " + " .. key, hl.dsp.workspace(i))',
            'end',
            'hl.bind(mod .. " + " .. key, hl.dsp.window.close())',
        ], {"mod": "SUPER", "COUNT": "10"})
        self.assertEqual(entries[0]["combo"], "SUPER + 1–10")
        self.assertEqual(entries[0]["description"], "Go to workspace · %1")
        self.assertEqual(entries[0]["detail"], "the number")
        self.assertEqual(entries[1]["combo"], "SUPER + key")

    def test_nested_calls_and_commas_do_not_split_the_key_expression(self):
        key, action = shortcuts.split_arguments(
            'make_key("A,B", { key = "Q" }), hl.dsp.focus({ direction = "left" })')
        self.assertEqual(key, 'make_key("A,B", { key = "Q" })')
        self.assertEqual(shortcuts.describe_action(action, {}), ("Change focus · %1", "left"))

    def test_named_and_anonymous_handlers(self):
        self.assertEqual(shortcuts.describe_action('enter_submap("screenshot")', {}),
                         ("enter submap · %1", "screenshot"))
        self.assertEqual(shortcuts.describe_action('function() reload_with_status() end', {}),
                         ("reload with status", ""))

    def test_unknown_dispatchers_and_commands_keep_their_meaning(self):
        self.assertEqual(shortcuts.describe_action('hl.dsp.custom_action("custom-mode")', {}),
                         ("custom action · %1", "custom-mode"))
        self.assertEqual(shortcuts.describe_action('hl.dsp.exec_cmd("echo Δ")', {}),
                         ("echo Δ", ""))
        self.assertEqual(shortcuts.describe_action('hl.dsp.exec_cmd("uwsm app -- foot")', {}),
                         ("Open %1", "foot"))

    def test_literal_resolution_rejects_partial_unknown_expressions(self):
        self.assertEqual(shortcuts.resolve_literal('"a" .. root .. "b"', {"root": "/"}), "a/b")
        self.assertIsNone(shortcuts.resolve_literal('"a" .. unknown .. "b"', {}))

    def test_discovery_order_and_shared_variable_resolution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config"
            config.mkdir()
            main = root / "hyprland.lua"
            main.write_text('hl.bind(mod .. " + Q", hl.dsp.window.close())\n')
            (config / "variables.lua").write_text('local mod = "SUPER"\nCOUNT = 10\n')
            (config / "binds.lua").write_text('hl.bind(mod .. " + W", hl.dsp.window.close())\n')
            (config / "k4.lua").write_text(
                'local root = "/tmp/code"\n'
                'local k4 = "quickshell ipc -p " .. root .. "/shell.qml call k4 "\n'
                'hl.bind(mod .. " + P", hl.dsp.exec_cmd(k4 .. "togglePanel"))\n')
            (config / "unrelated.lua").write_text('local setting = "unused"\n')
            with patch.object(shortcuts, "MAIN_CONFIG", str(main)), \
                    patch.object(shortcuts, "CONFIG", str(config)):
                self.assertEqual(shortcuts.config_files(),
                                 [str(main), str(config / "binds.lua"), str(config / "k4.lua")])
                values = shortcuts.read_variables()
                self.assertEqual(values["k4"], "quickshell ipc -p /tmp/code/shell.qml call k4 ")
                entries = shortcuts.read_shortcuts()
            self.assertEqual([entry["combo"] for entry in entries],
                             ["SUPER + Q", "SUPER + W", "SUPER + P"])
            self.assertEqual(entries[-1]["detail"], "togglePanel")

    def test_cli_uses_private_home_and_canonical_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            env = dict(os.environ, HOME=str(home))
            command = [sys.executable, "-B", str(Path(shortcuts.__file__).resolve())]
            empty = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(empty.stdout), {"total": 0, "shortcuts": []})
            config = home / ".config/hypr"
            config.mkdir(parents=True)
            (config / "hyprland.lua").write_text(
                '-- User actions\nhl.bind("SUPER + Q", hl.dsp.window.close())\n')
            result = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(result.stdout), {
                "total": 1, "shortcuts": [{"combo": "SUPER + Q",
                "description": "Close the window", "detail": "", "section": "User actions"}],
            })


if __name__ == "__main__":
    unittest.main()
