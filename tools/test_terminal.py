#!/usr/bin/env python3
"""Terminal regression tests, including a real PTY and isolated shell sessions.

Run with: python3 -B tools/test_terminal.py
"""

import errno
import hashlib
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "plugins/Terminal"))
from island import Island, Settings, Theme, key_bytes, mouse_bytes
from vt import VT


def screen(vt):
    return [vt.row_text(vt.screen_start + row).rstrip() for row in range(vt.rows)]


def session(vt):
    """Protocol object without spawning a child, for deterministic stream tests."""
    obj = Island.__new__(Island)
    obj.vt = vt
    vt.event_sink = obj._event
    obj.blocks, obj.command, obj.job = [], "", None
    obj.pending_password, obj.password_tail = None, ""
    obj.background_now = vt.default_bg
    obj.shell_pid = 0
    obj.input_buffer = bytearray()
    obj.search_row, obj.search_text = None, ""
    obj.mouse_button = "none"
    obj.dirty, obj.shell_gone = False, False
    return obj


class ScreenTests(unittest.TestCase):
    def test_scrolling_moves_lines_and_retains_history(self):
        vt = VT(12, 3)
        vt.feed(b"one\r\ntwo\r\nthree\r\nfour")
        self.assertEqual(screen(vt), ["two", "three", "four"])
        self.assertEqual(vt.row_text(0).rstrip(), "one")

    def test_scroll_region_and_reverse_index(self):
        vt = VT(12, 5)
        vt.feed(b"head\r\none\r\ntwo\r\nthree\r\nfoot")
        vt.feed(b"\x1b[2;4r\x1b[4;1H\n")
        self.assertEqual(screen(vt), ["head", "two", "three", "", "foot"])
        vt.feed(b"\x1b[2;1H\x1bM")
        self.assertEqual(screen(vt), ["head", "", "two", "three", "foot"])
        self.assertEqual(vt.history, [])

    def test_scrollback_limits_keep_stable_coordinates(self):
        vt = VT(12, 3, history_limit=2)
        for n in range(10):
            vt.feed(("line %d\r\n" % n).encode())
        self.assertEqual(len(vt.history), 2)
        self.assertEqual(vt.total, 11)
        self.assertEqual(vt.row_text(8).rstrip(), "line 8")
        vt.scroll_viewport(-2)
        self.assertEqual(vt.top, 6)
        vt.feed(b"next\r\n")
        self.assertEqual(vt.top, 7)  # The oldest line was evicted.

    def test_dcs_and_apc_end_without_swallowing_text(self):
        for sequence in (b"\x1bPignored", b"\x1b_Gignored"):
            vt = VT(20, 3)
            vt.feed(b"before" + sequence + b"\x1b")
            vt.feed(b"\\after")
            self.assertEqual(screen(vt)[0], "beforeafter")

    def test_resize_both_screens_and_restore_cursor(self):
        vt = VT(8, 3)
        vt.feed(b"main\x1b[?1049h\x1b7")
        vt.resize(20, 6)
        vt.feed(b"\x1b[?1049l")
        self.assertEqual((len(vt.grid), len(vt.grid[0])), (6, 20))
        self.assertEqual((vt.x, vt.y), (4, 0))
        vt.feed(b"\x1b[6;20HX")
        self.assertEqual(vt.grid[5][19][0], "X")
        vt.feed(b"\x1b7")
        vt.resize(5, 2)
        vt.feed(b"\x1b8Y")
        self.assertLess(vt.y, vt.rows)
        self.assertLess(vt.x, vt.cols)

    def test_rgb_groups_do_not_consume_following_attributes(self):
        for seq in (b"38;2;17;34;51;1", b"38:2::17:34:51;1", b"38:2:17:34:51;1"):
            vt = VT(20, 3)
            vt.feed(b"\x1b[" + seq + b"mX")
            run = vt.row_runs(0)[0]
            self.assertEqual(run["f"], "#112233")
            self.assertEqual(run["n"] & 2, 2)

    def test_reverse_default_colors(self):
        vt = VT(20, 3)
        vt.feed(b"\x1b[7mX")
        run = vt.row_runs(0)[0]
        self.assertEqual((run["f"], run["b"]), (vt.default_bg, vt.default_fg))

    def test_unicode_cells_copy_and_following_run_alignment(self):
        vt = VT(20, 3)
        vt.feed("e\u0301界😀x".encode())
        self.assertEqual(vt.x, 6)
        self.assertEqual(vt.row_text(0).rstrip(), "é界😀x")
        runs = vt.row_runs(0)
        self.assertEqual([(r["c"], r["width"]) for r in runs[:3]], [(1, 1), (2, 2), (4, 2)])
        self.assertEqual(session(vt).text_of(0, 0, 2, 3), "界")

    def test_combining_mark_on_last_column(self):
        vt = VT(3, 2)
        vt.feed("abe\u0301".encode())
        self.assertEqual(vt.row_text(0), "abé")

    def test_utf8_split_and_invalid_bytes_recover(self):
        vt = VT(20, 3)
        for byte in "café".encode():
            vt.feed(bytes([byte]))
        vt.feed(b"\xffok")
        self.assertEqual(vt.row_text(0).rstrip(), "café�ok")

    def test_hidden_cursor_and_scrolled_cursor(self):
        vt = VT(20, 3)
        obj = session(vt)
        vt.feed(b"\x1b[?25l")
        self.assertFalse(obj.frame()["cursor_visible"])
        vt.feed(b"\x1b[?25h1\r\n2\r\n3\r\n4")
        vt.scroll_viewport(-1)
        self.assertFalse(obj.frame()["cursor_visible"])

    def test_markers_use_position_at_marker_not_end_of_chunk(self):
        obj = session(VT(40, 8))
        obj._consume(b"\x1b]633;E;first\7\x1b]133;C\7one\r\ntwo\r\n"
                     b"\x1b]133;D;0\7\x1b]633;E;second\7\x1b]133;C\7three\r\n\x1b]133;D;1\7")
        self.assertEqual([(b["fila"], b["fin"], b["estado"]) for b in obj.blocks],
                         [(0, 2, "bien"), (2, 3, "mal")])

    def test_search_repeats_within_visible_page(self):
        obj = session(VT(20, 4))
        obj._consume(b"match one\r\nmatch two\r\nmatch three")
        with patch("island.say") as say:
            obj._search("match", -1)
            self.assertEqual(say.call_args.args[0]["fila"], 2)
            obj._search("match", -1)
            self.assertEqual(say.call_args.args[0]["fila"], 1)

    def test_input_backpressure_keeps_the_unwritten_suffix(self):
        obj = session(VT(20, 4))
        obj.master = 999
        obj._write_master("abcdef")
        with patch("island.os.write", side_effect=[2, BlockingIOError(errno.EAGAIN, "busy")]):
            obj._flush_input()
        self.assertEqual(obj.input_buffer, b"cdef")
        with patch("island.os.write", return_value=4):
            obj._flush_input()
        self.assertEqual(obj.input_buffer, b"")

    def test_keys_mouse_and_bracketed_paste(self):
        self.assertEqual(key_bytes("escape", False, False, False, False), "\x1b")
        self.assertEqual(mouse_bytes("pulsar", "izquierdo", 2, 3, True, True, True, True),
                         "\x1b[<28;2;3M")
        self.assertEqual(mouse_bytes("pulsar", "izquierdo", 200, 3, False, False, False, False),
                         b"\x1b[M \xe8#")
        obj = session(VT(20, 4))
        obj.vt.bracketed_paste = True
        obj.order(json.dumps({"que": "pegar", "valor": "one\ntwo"}))
        self.assertEqual(obj.input_buffer, b"\x1b[200~one\rtwo\x1b[201~")

    def test_mouse_drag_mode_only_reports_button_motion(self):
        obj = session(VT(20, 4))
        obj.vt.feed(b"\x1b[?1002h\x1b[?1006h")
        obj._order({"que": "raton", "tipo": "mover"})
        self.assertFalse(obj.input_buffer)
        obj._order({"que": "raton", "tipo": "pulsar", "boton": "derecho"})
        obj._order({"que": "raton", "tipo": "mover"})
        self.assertIn(b"\x1b[<34;1;1M", obj.input_buffer)

    def test_malformed_requests_do_not_crash_the_session(self):
        obj = session(VT(20, 4))
        with patch("island.notice"):
            for request in ("null", "[]", "{", '{"que":"medida","cols":"bad"}'):
                obj.order(request)
        obj._consume(b"still running")
        self.assertEqual(screen(obj.vt)[0], "still running")

    def test_config_preserves_hex_colors(self):
        with tempfile.TemporaryDirectory(prefix="k4-terminal-") as directory:
            path = Path(directory) / "config.json"
            path.write_text(json.dumps({"plugins": {"terminal": {"settings": {
                "background": "#112233", "ink": "#abcdef"}}}}))
            settings = Settings()
            settings.path = str(path)
            settings.read()
            self.assertEqual((settings.paper, settings.ink), ("#112233", "#abcdef"))


class PtyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="k4-terminal-")
        self.addCleanup(self.temp.cleanup)
        self.env = dict(os.environ, HOME=self.temp.name, XDG_CONFIG_HOME=self.temp.name,
                        XDG_STATE_HOME=self.temp.name, SHELL=shutil.which("bash"),
                        PS1="TEST_PROMPT> ", PROMPT_COMMAND="", PYTHONDONTWRITEBYTECODE="1")
        self.proc = None
        self.buffer = b""
        self.frames = []
        self.addCleanup(self.stop)

    def start(self, shell=None):
        if shell:
            self.env["SHELL"] = shell
        self.proc = subprocess.Popen([sys.executable, "-B", str(ROOT / "plugins/Terminal/island.py")],
                                     env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)

    def stop(self):
        if self.proc:
            if self.proc.poll() is None:
                self.proc.terminate()
                try:
                    self.proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait(timeout=3)
            for stream in (self.proc.stdin, self.proc.stdout, self.proc.stderr):
                stream.close()

    def send(self, request):
        self.proc.stdin.write((json.dumps(request) + "\n").encode())
        self.proc.stdin.flush()

    def wait_for(self, predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                message = json.loads(line)
                if message.get("que") == "marco":
                    self.frames.append(message)
                if predicate(message):
                    return message
            if select.select([self.proc.stdout], [], [], 0.1)[0]:
                data = os.read(self.proc.stdout.fileno(), 1048576)
                if not data:
                    self.fail("Backend exited: " + self.proc.stderr.read().decode())
                self.buffer += data
        self.fail("Timed out; last frame: " + repr(self.frames[-1:] if self.frames else []))

    def wait_text(self, text):
        return self.wait_for(lambda m: m.get("que") == "marco" and any(
            "".join(run["t"] for run in row).strip() == text for row in m["filas"]))

    def command(self, text):
        self.send({"que": "texto", "valor": text + "\r"})

    def test_real_shell_resize_and_clean_exit(self):
        self.start()
        self.wait_for(lambda m: m.get("que") == "marco")
        self.command("stty -echo; PS1='TEST_PROMPT> '")
        self.wait_text("TEST_PROMPT>")
        self.send({"que": "medida", "cols": 70, "filas": 12})
        self.command("stty size")
        self.wait_text("12 70")
        self.command("printf 'first\\nsecond\\n'")
        self.wait_text("second")
        self.command("exit")
        self.proc.wait(timeout=5)
        self.assertEqual(self.proc.returncode, 0)

    def test_large_paste_and_signal_cleanup(self):
        # A raw-mode foreground process checks every byte, avoiding the
        # canonical terminal driver's intentional per-line input limit.
        payload = ("0123456789abcdef" * 16384).encode()
        child = Path(self.temp.name) / "raw-shell"
        child.write_text("#!" + sys.executable + "\n" +
                         "import os, tty, hashlib, time\n"
                         "tty.setraw(0)\n"
                         "os.write(1, ('PID:%d\\r\\nREADY\\r\\n' % os.getpid()).encode())\n"
                         "data = bytearray()\n"
                         "while len(data) < 262144:\n"
                         "    data.extend(os.read(0, min(4096, 262144 - len(data))))\n"
                         "os.write(1, ('HASH:' + hashlib.sha256(data).hexdigest() + '\\r\\n').encode())\n"
                         "time.sleep(60)\n")
        child.chmod(0o700)
        self.start(str(child))
        frame = self.wait_text("READY")
        pid = int(next("".join(run["t"] for run in row).strip()[4:]
                       for row in frame["filas"] if "".join(run["t"] for run in row).startswith("PID:")))
        self.send({"que": "pegar", "valor": payload.decode()})
        self.wait_text("HASH:" + hashlib.sha256(payload).hexdigest())
        self.proc.terminate()
        self.proc.wait(timeout=3)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    @unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
    def test_zsh_marks_and_working_directory(self):
        zshrc = Path(self.temp.name) / ".zshrc"
        zshrc.write_text("source \"$K4TERM_INTEGRACION\"\nPS1='TEST_PROMPT> '\nstty -echo\n")
        self.env["ZDOTDIR"] = self.temp.name
        self.start(shutil.which("zsh"))
        self.wait_for(lambda m: m.get("que") == "ready")
        self.wait_text("TEST_PROMPT>")
        self.command("printf 'command-output\\n'")
        frame = self.wait_for(lambda m: m.get("que") == "marco" and m.get("ultimo")
                              and m["ultimo"]["estado"] == "bien")
        self.assertIn("printf", frame["ultimo"]["mandato"])
        self.command("cd /tmp")
        self.wait_for(lambda m: m.get("que") == "marco" and m.get("cwd") == "/tmp")


if __name__ == "__main__":
    unittest.main(verbosity=2)
