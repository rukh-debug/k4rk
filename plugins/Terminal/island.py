#!/usr/bin/env python3
#  island — the island terminal session, without k4term.
#
#  k4term-isla is a compiled thing (Ghostty's core, Rust) and this is
#  its stand-in: the same session —a shell in a PTY, its screen
#  served as JSON lines over the standard streams— carried in a
#  single script the bar can always run. When k4term IS installed it
#  steps aside without being asked: SesionIsla.qml picks the real
#  binary and nobody notices this file, which is the idea. A terminal
#  you already have beats one you must build.
#
#  The wire protocol is k4term-isla's, byte for byte, because the bar
#  already speaks it (SesionIsla.qml, TerminalIslaView.qml). That is
#  why the JSON keys below are Spanish — `que`, `marco`, `tecla`,
#  `filas`... — and stay that way: they are the contract, shared with
#  the compiled binary, not prose. Everything else in this file —
#  comments, identifiers, the messages meant for a person — is
#  English, as everywhere in this repo.
#
#  What this core cannot do is said plainly: it has no window, so
#  `emigrar` (handing the session to a k4term window) answers with a
#  notice instead, and the bar hides that door when k4term is not
#  around. Everything else —the folding of command outputs, the
#  prompt marks, passwords typed for you— works exactly as the
#  compiled one, because the shell integration speaks OSC 133/633
#  and that part is plain parsing.
#
#      python3 island.py               run, talking to the bar
#      python3 island.py --selftest    the test battery
#      python3 island.py --note        one Edinot note, from stdin

import errno
import fcntl
import json
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import termios
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vt import VT, color_256  # noqa: E402

COLS, ROWS = 90, 16
QUIET = 0.030    #  screen calm before a frame goes out
LONGEST = 0.120  #  longest a busy screen keeps one waiting
BLOCK_CAP = 400
try:
    JOB_THRESHOLD = max(0, float(os.environ.get("K4TERM_PILLAR_SECONDS", "3") or 3))
except ValueError:
    JOB_THRESHOLD = 3

#  The house gray for what asks for no attention (a folded block's
#  summary line); the same constant Theme.qml keeps on that side.
MUTED = "#8e8e93"

#  Agent marks never cross into a session: a shell that believed it
#  was «inside Claude» stops writing its transcript, and a terminal
#  someone opened from an agent inherits the belief silently. The
#  same list k4term keeps.
AGENT_MARKS = (
    "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH", "CLAUDE_PID",
    "CLAUDE_EFFORT", "AI_AGENT",
)

DEFAULT_FONT = "MesloLGS Nerd Font Mono"


def say(message):
    #  One line of JSON, flushed: the bar reads us line by line, and
    #  a half-line is a parse error on the other side. A broken pipe
    #  means the bar is gone; hanging a shell session off a dead
    #  parent is exactly what must not happen.
    try:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        raise SystemExit(0)


def notice(text):
    say({"que": "aviso", "texto": text})


def hex_color(text):
    #  Qt writes «#rrggbb», and «#aarrggbb» when there is alpha — the
    #  alpha goes FIRST, which is the trap of this format.
    clean = text.strip().lstrip("#")
    if len(clean) == 8:
        clean = clean[2:]
    if len(clean) != 6:
        return None
    try:
        return "#{:02x}{:02x}{:02x}".format(
            int(clean[0:2], 16), int(clean[2:4], 16), int(clean[4:6], 16))
    except ValueError:
        return None


def tint_color(name):
    #  A site's color by NAME, because what one means is «production
    #  is red», not a hexadecimal; a hand-written hex is honored.
    #  The Spanish names are k4term's stored values (hosts.json
    #  `tinte`), so they stay; English rides along for free.
    n = name.strip().lower()
    table = {
        "ambar": (0xFF, 0x9F, 0x0A), "ámbar": (0xFF, 0x9F, 0x0A),
        "amber": (0xFF, 0x9F, 0x0A), "orange": (0xFF, 0x9F, 0x0A),
        "naranja": (0xFF, 0x9F, 0x0A),
        "green": (0x30, 0xD1, 0x58), "verde": (0x30, 0xD1, 0x58),
        "blue": (0x0A, 0x84, 0xFF), "azul": (0x0A, 0x84, 0xFF),
        "purple": (0xBF, 0x5A, 0xF2), "morado": (0xBF, 0x5A, 0xF2),
        "pink": (0xFF, 0x37, 0x5F), "rosa": (0xFF, 0x37, 0x5F),
        "red": (0xFF, 0x45, 0x3A), "rojo": (0xFF, 0x45, 0x3A),
    }
    if n in table:
        return table[n]
    h = name.strip().lstrip("#")
    if len(h) == 6 and all(c in "0123456789abcdefABCDEF" for c in h):
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
    return None


def tinted_background(background, tint):
    #  A little tint, just enough to notice from the corner of the
    #  eye: reading over a saturated red is impossible, and the point
    #  is knowing where you are, not painting a wall.
    strength = 0.18
    return tuple(round(a * (1 - strength) + b * strength)
                 for a, b in zip(background, tint))


def asks_for_password(text):
    #  «assword:» covers Password/password at once, and the two
    #  Spanish shapes travel beside it. It must be the LAST thing
    #  written: a prompt leaves the stream stopped on it, a log that
    #  merely mentions it does not — and sudo's prompt ends in the
    #  user's name, which keeps it out on purpose.
    t = text.rstrip().lower()
    return t.endswith("assword:") or t.endswith("contrasena:") \
        or t.endswith("contraseña:")


def asks_about_fingerprint(text):
    t = text.rstrip().lower()
    return t.endswith("?") and "(yes/no" in t


# Canonical preferences. Native-terminal format conversion lives in the
# host's compatibility adapter; the bundled backend reads config.json.

class Settings:
    def __init__(self):
        self.font = DEFAULT_FONT
        self.size = 13.0
        self.trail = 8
        self.shell = None
        self.term = "xterm-256color"
        self.scrollback = 10000
        self.ink = None
        self.paper = None
        self.path = os.path.join(os.environ.get(
            "XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "k4", "config.json")

    def read(self):
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                settings = json.load(f).get("plugins", {}).get("terminal", {}).get("settings", {})
            for key, value in settings.items():
                self._apply(key, str(value))
        except (OSError, ValueError, AttributeError, TypeError):
            pass

    def _apply(self, key, value):
        if key == "font":
            self.font = value
        elif key == "size":
            try:
                self.size = min(72.0, max(6.0, float(value)))
            except ValueError:
                pass
        elif key == "trail":
            v = value.lower()
            if v in ("yes", "true"):
                self.trail = 8
            elif v in ("no", "false"):
                self.trail = 0
            else:
                try:
                    self.trail = min(24, max(0, int(float(value))))
                except ValueError:
                    pass
        elif key == "shell":
            self.shell = value
        elif key == "term":
            self.term = value
        elif key == "scrollback":
            try:
                self.scrollback = max(100, min(100000, int(value)))
            except ValueError:
                pass
        elif key == "ink" and hex_color(value):
            self.ink = hex_color(value)
        elif key == "background" and hex_color(value):
            self.paper = hex_color(value)

    def message(self):
        #  The wire names (`estela`, `fuente`, `tamano`) are the
        #  session protocol's, shared with k4term-isla.
        return {"que": "config", "estela": self.trail, "fuente": self.font,
                "tamano": self.size, "claves": True}


#  ── the theme the bar publishes ───────────────────────────────────
#
#  ~/.local/state/k4/tema.json, watched by mtime: no inotify in the
#  standard library, and one stat a second costs nothing.

class Theme:
    def __init__(self):
        self.path = os.environ.get(
            "K4TERM_TEMA",
            os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                         "k4/tema.json"))
        self.background = "#000000"
        self.ink = "#ffffff"

    def read(self):
        try:
            with open(self.path, "r", encoding="utf-8", errors="replace") as f:
                data = json.load(f)
            background = hex_color(data.get("fondo", ""))
            ink = hex_color(data.get("tinta", ""))
            if background and ink:
                self.background, self.ink = background, ink
                return True
        except (OSError, ValueError, TypeError, AttributeError):
            pass
        return False


#  ── the servers a shell may want to name ──────────────────────────
#
#  From ~/.ssh/config, the way k4term does it: names only, so what
#  runs inside can offer completions without seeing your keys.

def server_names_for_env():
    names, agents = [], []
    try:
        with open(os.path.expanduser("~/.ssh/config"), "r",
                  encoding="utf-8", errors="replace") as f:
            for line in f:
                clean = line.split("#")[0].strip()
                parts = clean.split()
                if len(parts) < 2 or parts[0].lower() != "host":
                    continue
                first = parts[1]
                if "*" in first or "?" in first:
                    continue
                (agents if first.endswith("-agentes") else names).append(first)
    except OSError:
        pass
    return " ".join(sorted(names)), " ".join(sorted(agents))


#  ── keys, as bytes ────────────────────────────────────────────────
#
#  The classic encoding every program understands. Kitty's progressive
#  keyboard is answered «unsupported» by the core, so nobody expects
#  it from us and every key has the one shape it always had.

ARROWS = {"up": "A", "down": "B", "right": "C", "left": "D"}
TILDE_KEYS = {"insert": 2, "delete": 3, "pageup": 5, "pagedown": 6}
LOW_F = {"f1": "P", "f2": "Q", "f3": "R", "f4": "S"}
HIGH_F = {"f5": 15, "f6": 17, "f7": 18, "f8": 19,
          "f9": 20, "f10": 21, "f11": 23, "f12": 24}


def key_bytes(name, shift, control, alt, app_cursor):
    m = 1 + (1 if shift else 0) + (2 if alt else 0) + (4 if control else 0)
    if name in ARROWS:
        if m > 1:
            return "\x1b[1;%d%s" % (m, ARROWS[name])
        return "\x1bO" + ARROWS[name] if app_cursor else "\x1b[" + ARROWS[name]
    if name == "home":
        if m > 1:
            return "\x1b[1;%dH" % m
        return "\x1bOH" if app_cursor else "\x1b[H"
    if name == "end":
        if m > 1:
            return "\x1b[1;%dF" % m
        return "\x1bOF" if app_cursor else "\x1b[F"
    if name in TILDE_KEYS:
        if m > 1:
            return "\x1b[%d;%d~" % (TILDE_KEYS[name], m)
        return "\x1b[%d~" % TILDE_KEYS[name]
    if name in LOW_F:
        if m > 1:
            return "\x1b[1;%d%s" % (m, LOW_F[name])
        return "\x1bO" + LOW_F[name]
    if name in HIGH_F:
        if m > 1:
            return "\x1b[%d;%d~" % (HIGH_F[name], m)
        return "\x1b[%d~" % HIGH_F[name]
    if name == "enter":
        if control:
            return "\n"
        if alt:
            return "\x1b\r"
        return "\r"
    if name == "backspace":
        if control:
            return "\x08"
        if alt:
            return "\x1b\x7f"
        return "\x7f"
    if name == "tab":
        return "\x1b[Z" if shift else "\t"
    if name == "escape":
        return "\x1b"
    return None


def mouse_bytes(kind, button, col, row, shift, control, alt, sgr):
    #  SGR is what everything speaks today; the old three-byte form
    #  stays for programs that never moved. Wheel events are presses
    #  only — no terminal sends their release.
    buttons = {"izquierdo": 0, "medio": 1, "derecho": 2, "none": 3,
               "arriba": 64, "abajo": 65}
    b = buttons.get(button, 0)
    mods = (4 if shift else 0) | (8 if alt else 0) | (16 if control else 0)
    cb = b | mods
    col = max(1, col)
    row = max(1, row)
    if sgr:
        if kind == "mover":
            cb |= 32
        final = "M" if kind != "soltar" else "m"
        return "\x1b[<%d;%d;%d%s" % (cb, col, row, final)
    if kind == "soltar":
        cb = 3 | mods
    if kind == "mover":
        cb |= 32
    return b"\x1b[M" + bytes(32 + min(v, 223) for v in (cb, col, row))


#  ── the session ───────────────────────────────────────────────────

class Island:
    def __init__(self):
        self.settings = Settings()
        self.settings.read()
        self.theme = Theme()
        self.theme.read()

        self.vt = VT(COLS, ROWS, self.settings.scrollback)
        self.vt.event_sink = self._event
        self.tint_name = ""
        self._apply_theme()

        #  The wire word for a command block is `bloques`, and each
        #  block travels as k4term-isla writes it: fila/estado/fin/
        #  mandato/plegado, history coordinates.
        self.blocks = []
        self.command = ""          #  the last thing 633;E said
        self.background_now = self.vt.default_bg

        #  Work in progress, announced only once it crosses the
        #  threshold WHILE ALIVE: an `ls` costs nobody a message.
        self.job = None            # [command, since, announced]

        #  The password somebody may be asked for, until asked or
        #  thirty seconds gone. Never shown, never stored.
        self.pending_password = None   # (value, since)
        self.password_tail = ""

        self.dirty = False
        self.dirty_since = None
        self.input_buffer = bytearray()
        self.mouse_button = "none"
        self.search_row = None
        self.search_text = ""

        self.shell_pid, self.master = self._spawn()
        self.shell_gone = False

        #  The note-taking child, when there is one: its stdout line
        #  becomes the user's notice, so the loop never blocks on a
        #  server that takes half a minute to answer.
        self.note_child = None
        self.note_fd = None

        self._stamp_files()

    # ── birth ───────────────────────────────────────────────────

    def _spawn(self):
        shell = self.settings.shell or os.environ.get("SHELL") or shutil.which("sh")
        shell = shutil.which(shell) if shell else None
        if not shell:
            raise RuntimeError("The configured terminal shell could not be found")
        master, slave = pty.openpty()
        fcntl.ioctl(master, termios.TIOCSWINSZ,
                    struct.pack("HHHH", ROWS, COLS, 0, 0))

        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            if slave > 2:
                os.close(slave)
            os.chdir(os.path.expanduser("~"))
            env = dict(os.environ)
            for mark in AGENT_MARKS:
                env.pop(mark, None)
            env["TERM"] = self.settings.term
            env["COLORTERM"] = "truecolor"
            #  The shell integration hooks on this name: it is what
            #  tells zsh «you may emit the marks».
            env["TERM_PROGRAM"] = "k4term"
            env["K4TERM_INTEGRACION"] = os.path.join(os.path.dirname(__file__), "integration.zsh")
            for mark in ("TMUX", "TMUX_PANE", "STY"):
                env.pop(mark, None)
            names, agents = server_names_for_env()
            if names:
                env["K4_SERVIDORES"] = names
            if agents:
                env["K4_SERVIDORES_AGENTES"] = agents
            argv = [shell]
            if os.path.basename(shell) == "fish":
                #  fish probes the terminal and WAITS for the answer;
                #  a session with no window never answers, and the
                #  first prompt showed up seconds late. k4term turns
                #  the probe off; so do we.
                argv += ["--features", "no-query-term"]
            argv += ["-l"]
            try:
                os.execve(shell, ["-" + os.path.basename(shell)] + argv[1:], env)
            except OSError as error:
                os.write(2, ("Could not start terminal shell: %s\r\n" % error).encode())
                os._exit(127)

        os.close(slave)
        return pid, master

    def _apply_theme(self):
        background = self.settings.paper or self.theme.background
        ink = self.settings.ink or self.theme.ink
        #  A tint from the servers plugin rides on top of the house
        #  theme, and the theme is re-read each time: the bar may
        #  change it while you are inside a server.
        tint = tint_color(self.tint_name)
        if tint:
            background = "#{:02x}{:02x}{:02x}".format(
                *tinted_background(
                    tuple(int(background[i:i + 2], 16) for i in (1, 3, 5)), tint))
        self.vt.default_bg = background
        self.vt.default_fg = ink
        self.background_now = background

    def _stamp_files(self):
        def stamp(path):
            try:
                return os.stat(path).st_mtime_ns
            except OSError:
                return 0
        self._stamp_settings = stamp(self.settings.path)
        self._stamp_theme = stamp(self.theme.path)

    def _watch_files(self):
        try:
            if os.stat(self.settings.path).st_mtime_ns != self._stamp_settings:
                self._stamp_settings = os.stat(self.settings.path).st_mtime_ns
                self.settings = Settings()
                self.settings.read()
                say(self.settings.message())
                self.vt.history_limit = self.settings.scrollback
                self.vt.trim_history()
                self._apply_theme()
                self.dirty = True
        except OSError:
            pass
        try:
            if os.stat(self.theme.path).st_mtime_ns != self._stamp_theme:
                self._stamp_theme = os.stat(self.theme.path).st_mtime_ns
                if self.theme.read():
                    self._apply_theme()
                    self.dirty = True
        except OSError:
            pass

    # ── output ──────────────────────────────────────────────────

    def _cwd(self):
        try:
            return os.readlink("/proc/%d/cwd" % self.shell_pid)
        except OSError:
            return ""

    def _summary(self, block):
        how_many = block["fin"] - block["fila"]
        command = block["mandato"].strip()
        if len(command) > 46:
            command = command[:45] + "…"
        text = ("▸ %s · %d lines" % (command, how_many)) if command \
            else ("▸ %d lines" % how_many)
        return [{"t": text, "f": MUTED, "b": self.background_now, "n": 0, "c": 1}]

    @staticmethod
    def _folded_at(blocks, row):
        for b in blocks:
            if b["plegado"] and b["fin"] > b["fila"] and b["fila"] <= row < b["fin"]:
                return b
        return None

    def frame(self):
        #  `marco` — the screen as the bar paints it. Rows of runs,
        #  each with the history row it stands for, folded blocks as
        #  one summary line, and the cursor placed by its true row.
        vt = self.vt
        top, total = vt.top, vt.total
        rows, rows_abs, folded = [], [], []
        r = 0
        while r < vt.rows:
            abs_row = top + r
            block = None if vt.alt_screen else self._folded_at(self.blocks, abs_row)
            if block:
                rows.append(self._summary(block))
                rows_abs.append(block["fila"])
                folded.append(len(rows) - 1)
                after = block["fin"] - top
                if after <= r:
                    break
                r = after
                continue
            rows.append(vt.row_runs(abs_row))
            rows_abs.append(abs_row)
            r += 1

        #  The cursor goes by its true history row, which may have
        #  moved when something above folded; if it is inside the
        #  fold it stays at the end — the least false place.
        cursor_abs = vt.cursor_abs_row()
        cursor_row = rows_abs.index(cursor_abs) + 1 if cursor_abs in rows_abs \
            else 0
        used = 0
        for i, row in enumerate(rows):
            if row:
                used = i + 1

        bottom = top + vt.rows
        self.blocks = [b for b in self.blocks if b["fin"] == 0 or b["fin"] > vt.history_start]
        visible = [] if vt.alt_screen else [b for b in self.blocks if top <= b["fila"] < bottom]

        return {
            "que": "marco",
            "filas": rows,
            "filas_abs": rows_abs,
            "resumidas": folded,
            "cursor": [vt.x + 1, cursor_row],
            "cursor_visible": vt.cursor_visible and cursor_row > 0,
            "cursor_figura": vt.cursor_shape,
            "cursor_parpadea": vt.cursor_blinks,
            "cols": vt.cols,
            "filas_n": vt.rows,
            "usadas": max(used, cursor_row),
            "cwd": self._cwd(),
            "titulo": vt.title,
            "scroll": [0, vt.rows] if vt.alt_screen else [top - vt.history_start, total - vt.history_start],
            "raton": vt.mouse_active,
            "bloques": visible,
            "ultimo": self.blocks[-1] if self.blocks and not vt.alt_screen else None,
        }

    # ── stream events ───────────────────────────────────────────

    def _event(self, kind, value):
        if kind == "prompt":
            say({"que": "ready"})
        elif kind == "reset":
            self.blocks = []
        elif kind == "command":
            self.command = value
        elif kind == "start":
            self.blocks.append({"fila": self.vt.cursor_abs_row(),
                                "estado": "corre", "fin": 0,
                                "mandato": self.command, "plegado": False})
            if len(self.blocks) > BLOCK_CAP:
                del self.blocks[0]
            if self.job is None:
                self.job = [self.command, time.monotonic(), False]
        elif kind == "finish":
            if self.blocks and self.blocks[-1]["estado"] == "corre":
                last = self.blocks[-1]
                last["estado"] = "bien" if value == 0 else "mal"
                last["fin"] = self.vt.cursor_abs_row()
            #  The command that was going to ask for the password is
            #  over: nobody will ask now, and a later prompt must not
            #  be answered with this server's secret.
            self.pending_password = None
            self.password_tail = ""
            if self.job is not None:
                command, since, announced = self.job
                self.job = None
                if announced:
                    say({"que": "trabajo", "estado": "acaba", "mandato": command,
                         "salida": value,
                         "segundos": round(time.monotonic() - since)})
        elif kind == "bell":
            say({"que": "campana", "titulo": self.command})
        elif kind == "clipboard":
            say({"que": "portapapeles", "texto": value})
        elif kind == "notice":
            title, body = value
            text = body if title == "k4term" else "%s — %s" % (title, body)
            notice(text.strip())

    def _consume(self, data):
        self.vt.feed(data)
        if self.vt.replies:
            #  A program that asked is waiting: the answer leaves with
            #  the same breath as the bytes that asked for it.
            self._write_master(b"".join(self.vt.replies))
            self.vt.replies = []
        self._watch_password(data)

    def _watch_password(self, data):
        if self.pending_password is None:
            self.password_tail = ""
            return
        value, since = self.pending_password
        self.password_tail = (self.password_tail +
                              data.decode("utf-8", "replace"))[-512:]
        now = time.monotonic()
        if now - since > 30:
            self.pending_password = None
            self.password_tail = ""
        elif asks_for_password(self.password_tail):
            self.pending_password = None
            self.password_tail = ""
            self._write_master((value + "\r").encode())
        elif asks_about_fingerprint(self.password_tail):
            #  The fingerprint question is not the password: after
            #  «yes» the password still comes. Only the tail is spent.
            self.password_tail = ""
            self._write_master(b"yes\r")

    # ── work in progress, told at the right moment ───────────────

    def _job_tick(self):
        if self.job is None:
            return
        command, since, announced = self.job
        if not announced and time.monotonic() - since >= JOB_THRESHOLD:
            self.job = [command, since, True]
            say({"que": "trabajo", "estado": "empieza", "mandato": command,
                 "salida": 0, "segundos": round(time.monotonic() - since)})

    # ── history as text ──────────────────────────────────────────

    def text_of(self, start, end, col_start, col_end):
        #  Rows start..end (inclusive; end 0 means «as far as it
        #  goes»), trimmed of trailing whitespace, empty tail
        #  dropped. The column cuts are what make a dragged selection
        #  be what is seen and not whole rows — and with ONE row both
        #  cuts apply at once, or the good part is cut away.
        vt = self.vt
        start = max(start, vt.history_start)
        stop = vt.total - 1 if end == 0 and not col_end else min(end, vt.total - 1)
        lines = []
        for r in range(start, stop + 1):
            first = max(0, col_start - 1) if r == start else 0
            last = col_end if r == stop and col_end else None
            text = vt.row_slice(r, first, last)
            lines.append(text if r == stop and col_end else text.rstrip())
        while lines and lines[-1] == "":
            lines.pop()
        return "\n".join(lines)

    # ── orders from the bar ──────────────────────────────────────

    def order(self, line):
        try:
            m = json.loads(line)
            if not isinstance(m, dict):
                return
            self._order(m)
        except (ValueError, TypeError, OverflowError, struct.error):
            notice("Invalid terminal request")

    def _order(self, m):
        if not isinstance(m.get("que"), str):
            return
        kind = m.get("que")
        vt = self.vt
        if kind == "texto":
            self._write_master(m.get("valor", ""))
        elif kind == "tecla":
            data = key_bytes(m.get("nombre", ""), m.get("shift", False),
                             m.get("control", False), m.get("alt", False),
                             vt.app_cursor)
            if data:
                self._write_master(data)
        elif kind == "pegar":
            payload = str(m.get("valor", "")).replace("\r\n", "\n").replace("\n", "\r")
            if vt.bracketed_paste:
                payload = payload.replace("\x1b", "")
                payload = "\x1b[200~" + payload + "\x1b[201~"
            self._write_master(payload)
        elif kind == "medida":
            cols = max(20, min(500, int(m.get("cols", COLS))))
            rows = max(4, min(200, int(m.get("filas", ROWS))))
            try:
                fcntl.ioctl(self.master, termios.TIOCSWINSZ,
                            struct.pack("HHHH", rows, cols, 0, 0))
            except OSError:
                pass
            vt.resize(cols, rows)
            self.dirty = True
        elif kind == "pinta":
            self.dirty = True
        elif kind == "donde":
            say({"que": "donde", "ruta": self._cwd()})
        elif kind == "rueda":
            lines = m.get("lineas", 0)
            if vt.mouse_active and not m.get("historial"):
                button = "arriba" if lines < 0 else "abajo"
                for _ in range(min(abs(lines), 10)):
                    self._write_master(mouse_bytes(
                        "pulsar", button, m.get("col", 1), m.get("fila", 1),
                        False, False, False, vt.mouse_sgr))
            else:
                vt.scroll_viewport(lines)
                self.dirty = True
        elif kind == "tope":
            vt.scroll_viewport_edge(m.get("arriba", False))
            self.dirty = True
        elif kind == "raton":
            if vt.mouse_active:
                event = m.get("tipo", "pulsar")
                button = m.get("boton", "izquierdo")
                if event == "pulsar":
                    self.mouse_button = button
                moving = event == "mover"
                wanted = (not moving and (event != "soltar" or vt.mouse_mode != 9)) \
                    or vt.mouse_mode == 1003 \
                    or (moving and vt.mouse_mode == 1002 and self.mouse_button != "none")
                if wanted:
                    self._write_master(mouse_bytes(
                        event, self.mouse_button if moving else button,
                        m.get("col", 1), m.get("fila", 1),
                        m.get("shift", False), m.get("control", False),
                        m.get("alt", False), vt.mouse_sgr))
                if event == "soltar":
                    self.mouse_button = "none"
        elif kind == "texto_de":
            say({"que": "texto",
                 "texto": self.text_of(m.get("desde", 0), m.get("hasta", 0),
                                       m.get("col_desde", 0),
                                       m.get("col_hasta", 0)),
                 "motivo": m.get("motivo", "")})
        elif kind == "saltar":
            top = vt.top
            if m.get("hacia", -1) < 0:
                target = next((b["fila"] for b in reversed(self.blocks)
                               if b["fila"] < top), None)
            else:
                target = next((b["fila"] for b in self.blocks
                               if b["fila"] > top), None)
            if target is not None:
                vt.scroll_viewport(target - top)
                self.dirty = True
        elif kind == "buscar":
            self._search(m.get("texto", ""), m.get("hacia", -1))
        elif kind == "tinte":
            self.tint_name = m.get("color", "")
            self._apply_theme()
            self.dirty = True
        elif kind == "clave":
            value = m.get("valor", "")
            self.pending_password = (value, time.monotonic()) if value else None
            self.password_tail = ""
        elif kind == "plegar":
            for b in self.blocks:
                if b["fila"] == m.get("fila"):
                    b["plegado"] = not b["plegado"]
                    self.dirty = True
                    break
        elif kind == "nota":
            self._note(m.get("entera", False))
        elif kind == "emigrar":
            #  Handing the session to a window takes a window that
            #  can adopt it; only k4term's can. Said out loud because
            #  a silently swallowed order is a button that does
            #  nothing, and that reads as broken.
            notice("Moving the session to a window needs k4term installed")

    def _write_master(self, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        self.input_buffer.extend(data)

    def _flush_input(self):
        # PTYs apply backpressure, especially during large pastes. Retain
        # the unwritten suffix and retry only when select reports writable.
        while self.input_buffer:
            try:
                count = os.write(self.master, self.input_buffer[:65536])
                if count == 0:
                    return
                del self.input_buffer[:count]
            except OSError as e:
                if e.errno == errno.EINTR:
                    continue
                if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                    self.shell_gone = True
                    self.input_buffer.clear()
                return

    def _search(self, text, direction):
        vt = self.vt
        needle = text.lower()
        top, total = vt.top, vt.total
        found = None
        if needle:
            start = self.search_row if needle == self.search_text and self.search_row is not None \
                else (total if direction < 0 else vt.history_start - 1)
            candidates = range(start - 1, vt.history_start - 1, -1) if direction < 0 \
                else range(start + 1, total)
            for r in candidates:
                if needle in vt.row_text(r).lower():
                    found = r
                    break
        self.search_row, self.search_text = found, needle
        if found is not None:
            vt.scroll_viewport(found - top)
            self.dirty = True
        say({"que": "buscado", "hay": found is not None,
             "fila": found if found is not None else top})

    #  ── notes, out of the loop's way ──────────────────────────────

    def _note(self, whole):
        if whole:
            title, body = "Terminal session", self.text_of(0, 0, 0, 0)
        elif self.blocks:
            b = self.blocks[-1]
            title = "Command output"
            body = self.text_of(b["fila"], max(b["fin"] - 1, 0), 0, 0)
        else:
            title, body = "", ""
        if not body.strip():
            notice("There is nothing to note")
            return
        if not edinot_available():
            notice("Edinot is not open")
            return
        if self.note_child is not None:
            return
        ask_r, ask_w = os.pipe()        #  the petition goes down this one
        answer_r, answer_w = os.pipe()  #  the outcome comes up this one
        pid = os.fork()
        if pid == 0:
            os.close(ask_w)
            os.close(answer_r)
            try:
                os.close(self.master)
            except OSError:
                pass
            os.dup2(ask_r, 0)
            os.dup2(answer_w, 1)
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, 2)
            os.closerange(3, 256)
            os.execv(sys.executable,
                     [sys.executable, os.path.abspath(__file__), "--note"])
        os.close(ask_r)
        os.close(answer_w)
        try:
            os.write(ask_w, json.dumps(
                {"titulo": title, "cuerpo": body}).encode())
        finally:
            os.close(ask_w)
        self.note_child = pid
        self.note_fd = answer_r
        os.set_blocking(self.note_fd, False)

    def _collect_note(self):
        try:
            chunk = os.read(self.note_fd, 4096)
        except (BlockingIOError, OSError):
            return
        if not chunk:
            os.close(self.note_fd)
            self.note_fd = None
            try:
                os.waitpid(self.note_child, 0)
            except OSError:
                pass
            self.note_child = None
            return
        for line in chunk.decode("utf-8", "replace").splitlines():
            if line.strip():
                notice(line.strip())

    # ── the loop ─────────────────────────────────────────────────

    def run(self):
        #  The settings go BEFORE the first frame: the island paints
        #  its first cursor with the trail the user chose and not
        #  with the default, corrected a beat later.
        say(self.settings.message())

        wake_r, wake_w = os.pipe()
        os.set_blocking(wake_r, False)
        os.set_blocking(wake_w, False)
        signal.set_wakeup_fd(wake_w)
        signal.signal(signal.SIGCHLD, lambda *_: None)
        def stop(*_):
            raise SystemExit(0)
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGHUP, stop)

        stdin_fd = sys.stdin.fileno()
        os.set_blocking(stdin_fd, False)
        os.set_blocking(self.master, False)
        in_buffer = b""
        file_tick = 0.0

        try:
            while True:
                now = time.monotonic()
                timeout = 1.0
                if self.dirty:
                    if self.dirty_since is None:
                        self.dirty_since = now
                    timeout = min(timeout, QUIET,
                                  max(0.0, LONGEST - (now - self.dirty_since)))
                watchers = [self.master, stdin_fd, wake_r]
                if self.note_fd is not None:
                    watchers.append(self.note_fd)
                try:
                    ready, writable, _ = select.select(
                        watchers, [self.master] if self.input_buffer else [], [], timeout)
                except InterruptedError:
                    continue

                if self.master in writable:
                    self._flush_input()

                if stdin_fd in ready:
                    try:
                        chunk = os.read(stdin_fd, 65536)
                    except BlockingIOError:
                        chunk = None
                    if chunk == b"":
                        break   #  the bar closed the pipe: we go too
                    if chunk:
                        in_buffer += chunk
                        while b"\n" in in_buffer:
                            line, in_buffer = in_buffer.split(b"\n", 1)
                            if line.strip():
                                self.order(line.decode("utf-8", "replace"))

                if self.master in ready or self.shell_gone:
                    # Yield to keyboard input and frame delivery even if a
                    # command can fill the PTY faster than we can drain it.
                    for _ in range(4):
                        try:
                            chunk = os.read(self.master, 65536)
                        except OSError as e:
                            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                                break
                            chunk = b""   #  EIO: the shell is gone
                        if chunk:
                            self._consume(chunk)
                            self.dirty = True
                            if self.dirty_since is None:
                                self.dirty_since = time.monotonic()
                        else:
                            self.shell_gone = True
                            break
                    if self.shell_gone and self._shell_reaped():
                        if self.dirty:
                            say(self.frame())
                        break

                if self.note_fd is not None and self.note_fd in ready:
                    self._collect_note()

                if wake_r in ready:
                    try:
                        os.read(wake_r, 4096)
                    except OSError:
                        pass
                    self._reap()

                if time.monotonic() - file_tick >= 1.0:
                    file_tick = time.monotonic()
                    self._watch_files()
                    self._job_tick()

                #  The frame: once the screen is quiet (the select
                #  above timed out with nothing to read), or once a
                #  busy screen has waited long enough.
                if self.dirty and (not ready or
                                   (self.dirty_since is not None and
                                    time.monotonic() - self.dirty_since >= LONGEST)):
                    say(self.frame())
                    self.dirty = False
                    self.dirty_since = None
        finally:
            signal.set_wakeup_fd(-1)
            os.close(wake_r)
            os.close(wake_w)
            self._shutdown()

    def _shutdown(self):
        groups = {self.shell_pid}
        try:
            groups.add(os.tcgetpgrp(self.master))
        except OSError:
            pass
        for group in groups:
            try:
                if group > 0 and group != os.getpgrp():
                    os.killpg(group, signal.SIGHUP)
            except OSError:
                pass
        os.close(self.master)
        deadline = time.monotonic() + 0.5
        while not self._shell_reaped() and time.monotonic() < deadline:
            time.sleep(0.01)
        for group in groups:
            try:
                if group > 0 and group != os.getpgrp():
                    os.killpg(group, signal.SIGKILL)
            except OSError:
                pass
        try:
            os.waitpid(self.shell_pid, 0)
        except ChildProcessError:
            pass
        if self.note_fd is not None:
            os.close(self.note_fd)
        if self.note_child is not None:
            try:
                os.kill(self.note_child, signal.SIGTERM)
                os.waitpid(self.note_child, 0)
            except (OSError, ChildProcessError):
                pass

    def _shell_reaped(self):
        try:
            pid, _ = os.waitpid(self.shell_pid, os.WNOHANG)
            return pid == self.shell_pid
        except ChildProcessError:
            return True

    def _reap(self):
        try:
            while True:
                pid, _ = os.waitpid(-1, os.WNOHANG)
                if pid == 0:
                    break
                if pid == self.shell_pid:
                    self.shell_gone = True
                if pid == self.note_child and self.note_fd is not None:
                    self._collect_note()
        except (ChildProcessError, OSError):
            pass


#  ── Edinot, one note at a time ────────────────────────────────────

def edinot_server_path():
    return os.path.join(os.environ.get(
        "XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
        "edinot", "mcp-server.mjs")


def edinot_available():
    if not os.path.exists(edinot_server_path()):
        return False
    for path in os.environ.get("PATH", "").split(os.pathsep):
        if path and os.access(os.path.join(path, "node"), os.X_OK):
            return True
    return False


def run_as_note_child():
    #  `--note`: one Edinot note, the title and body read from stdin,
    #  the outcome written as a single line. Kept in a child process
    #  because the MCP server takes its time hooking the live app,
    #  and the session must keep painting meanwhile.
    import subprocess
    import threading
    request = json.loads(sys.stdin.read() or "{}")
    title = request.get("titulo", "")
    body = request.get("cuerpo", "")
    server = edinot_server_path()
    if not os.path.exists(server):
        sys.stdout.write("Edinot is not open\n")
        return

    child = subprocess.Popen(
        ["node", server], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, env=dict(os.environ, EDINOT_AGENT_KIND="k4"))

    def rpc(id_, method, params):
        child.stdin.write((json.dumps(
            {"jsonrpc": "2.0", "id": id_, "method": method,
             "params": params}) + "\n").encode())
        child.stdin.flush()
        found = [None]

        def reader():
            for raw in child.stdout:
                try:
                    value = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    continue
                if value.get("id") == id_:
                    found[0] = value
                    return
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        thread.join(30)
        return found[0]

    try:
        rpc(0, "initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "k4", "version": "0.1"}})
        child.stdin.write((json.dumps(
            {"jsonrpc": "2.0", "method": "notifications/initialized"})
            + "\n").encode())
        child.stdin.flush()
        today = rpc(1, "tools/call",
                    {"name": "get_or_create_daily_note", "arguments": {}})
        name = None
        try:
            name = json.loads(today["result"]["content"][0]["text"])["name"]
        except (KeyError, IndexError, TypeError, ValueError):
            pass
        if not name:
            sys.stdout.write("The daily note could not be opened\n")
            return
        #  In a code block: a terminal's output should read as what it
        #  is, with its dashes and asterisks untouched.
        content = "\n## %s\n\n```\n%s\n```\n" % (title, body.rstrip())
        rpc(2, "tools/call", {"name": "append_note",
                              "arguments": {"name": name, "content": content}})
        sys.stdout.write("Saved in %s\n" % name)
    finally:
        try:
            child.stdin.close()
            child.wait(timeout=5)
        except OSError:
            pass


#  ── the test battery ──────────────────────────────────────────────

def selftest():
    from vt import VT as V
    failures = []

    def check(claim, name):
        if not claim:
            failures.append(name)

    #  Text lands where it should and wraps when it must.
    v = V(10, 4)
    v.feed(b"abcdefghij")
    check(v.row_text(0).rstrip() == "abcdefghij" and v.x == 9
          and v._wrap_pending,
          "the last column waits: the wrap is pending, not forced")
    v.feed(b"kZ")
    check(v.row_text(0).rstrip() == "abcdefghij" and v.row_text(1).rstrip() == "kZ",
          "the pending wrap wrote at the head of the next line")

    v = V(10, 4)
    v.feed(b"\x1b[?7l" + b"m" * 12)
    check(v.x == 9 and v.row_text(0)[9] == "m",
          "without autowrap the last column is overwritten")

    #  Colors and attributes come out as runs with their column.
    v = V(20, 4)
    v.feed(b"\x1b[1;31mred\x1b[0m plain")
    runs = v.row_runs(0)
    check(runs[0]["t"] == "red" and runs[0]["f"] == "#cd3133"
          and runs[0]["n"] & 2, "SGR red+bold is a run with its color")
    check(runs[1]["t"].startswith(" plain") and runs[1]["c"] == 4,
          "the run after the reset starts at its column")

    v = V(20, 4)
    v.feed(b"\x1b[38;2;17;34;51mX")
    check(v.row_runs(0)[0]["f"] == "#112233", "truecolor arrives as itself")

    v = V(20, 4)
    v.feed(b"\x1b[38:2::10:20:30mX")
    check(v.row_runs(0)[0]["f"] == "#0a141e", "colon truecolor is the same color")

    #  Reverse is resolved away, swapped.
    v = V(20, 4)
    v.feed(b"\x1b[7;37;40mhi")
    run = v.row_runs(0)[0]
    check(run["f"] == "#000000" and run["b"] == "#e5e5e5",
          "reverse swaps fg and bg at dump time")

    #  The palette can be redefined and old cells follow.
    v = V(20, 4)
    v.feed(b"\x1b[31mX\x1b]4;1;rgb:ff/00/ff\x1b\\")
    check(v.row_runs(0)[0]["f"] == "#ff00ff",
          "OSC 4 repaints what was already written")

    #  The tail of a blank row is trimmed, colored space is kept.
    v = V(20, 4)
    v.feed(b"hi\x1b[41m   \x1b[0m")
    runs = v.row_runs(0)
    check(len(runs) == 2 and runs[1]["b"] == "#cd3133",
          "colored spaces stay, the default tail is dropped")

    #  Wide characters and combining marks.
    v = V(10, 4)
    v.feed("日".encode())
    check(v.row_text(0).rstrip() == "日" and v.x == 2,
          "a wide glyph takes two cells")
    v = V(10, 4)
    v.feed("é".encode())
    check(v.row_text(0).rstrip() == "\u00e9" and v.x == 1,
          "a combining mark joins the cell before it")

    #  The dump's arithmetic contract: ONE codepoint per cell, or the
    #  view — which multiplies a run's text length by the cell width —
    #  drifts the line to the right of every accent.
    v = V(20, 4)
    v.feed("caf".encode() + "é".encode() + b" and more")
    check(v.row_text(0).rstrip() == "caf\u00e9 and more" and v.x == 13,
          "an accented letter retains its text and cell position")

    #  A wide glyph writes its continuation cell, not stale content.
    v = V(10, 4)
    v.feed(b"stale")
    v.feed(b"\r" + "日y".encode())
    check(v.row_text(0).rstrip() == "\u65e5yle",
          "the cell after a wide glyph is blank, not yesterday's")

    #  Cursor shapes, as the programs ask for them (DECSCUSR).
    v = V(10, 4)
    v.feed(b"\x1b[4 q")
    check(v.cursor_shape == "subrayado" and not v.cursor_blinks,
          "a steady underline is understood")
    v.feed(b"\x1b[0 q")
    check(v.cursor_shape == "bloque" and v.cursor_blinks,
          "and the default block blinks")

    #  DEC graphics.
    v = V(10, 4)
    v.feed(b"\x1b(0qq\x1b(Bq")
    check(v.row_text(0)[:2] == "──" and v.row_text(0)[2] == "q",
          "the graphics charset draws lines and then stops")

    #  The alternate screen comes and goes, and restores.
    v = V(10, 4)
    v.feed(b"antes")
    v.feed(b"\x1b[?1049h\x1b[2J\x1b[HTUI")
    check(v.row_text(0).rstrip() == "TUI", "the alt screen starts clean")
    v.feed(b"\x1b[?1049l")
    check(v.row_text(0).rstrip() == "antes" and v.x == 5,
          "leaving the alt screen puts the old one back")

    #  Scroll margins: a region scrolls inside itself and the
    #  scrollback stays out of it.
    v = V(10, 5)
    v.feed(b"\x1b[2;3r" + b"uno\r\n")
    for i in range(6):
        v.feed(("%d\n" % i).encode())
    check(len(v.history) == 0, "a region's scrolling never feeds history")
    v.feed(b"\x1b[r")
    for i in range(9):
        v.feed(("%d\n" % i).encode())
    check(len(v.history) >= 5, "the whole screen scrolls into history")

    #  The viewport stays anchored while output flows below.
    v = V(10, 4)
    for i in range(20):
        v.feed(("line %d\r\n" % i).encode())
    check(v.scrolled == 0 and v.top == v.total - v.rows,
          "the view follows the output and does not drift up history")
    v.scroll_viewport(-3)
    top_before = v.top
    for i in range(5):
        v.feed(("more %d\r\n" % i).encode())
    check(v.top == top_before,
          "reading from up there does not follow the new output")
    v.scroll_viewport_edge(False)
    check(v.top == v.total - v.rows, "the bottom is the bottom")

    #  Erase keeps the background it was given.
    v = V(10, 4)
    v.feed(b"\x1b[41m\x1b[K")
    check(v.row_runs(0)[0]["b"] == "#cd3133",
          "a red erase stays red (BCE)")

    #  Links travel inside the run.
    v = V(20, 4)
    v.feed(b"\x1b]8;;https://k4.example\x1b\\k4\x1b]8;;\x1b\\")
    check(v.row_runs(0)[0].get("u") == "https://k4.example",
          "OSC 8 hangs the link off its words")

    #  The markers, split across reads and with either ending.
    v = V(10, 4)
    v.feed(b"\x1b]133;")
    v.feed(b"C\x07")
    check([e[1] for e in v.events] == ["start"],
          "a marker split across reads is still seen")
    v.feed(b"\x1b]133;D;130\x1b\\")
    check([e[1] for e in v.events] == ["finish"] and v.events[0][2] == 130,
          "the long ending carries the exit code")
    v.feed(b"\x1b]633;E;cargo build\x07")
    check(v.events[0][1] == "command" and v.events[0][2] == "cargo build",
          "the command line is read from 633;E")
    v.feed(b"ojo\x07")
    check(v.events[0][1] == "bell", "a bare BEL is the bell")
    v.feed(b"\x1b]633;E;ls\x07")
    check([e[1] for e in v.events] == ["command"],
          "the BEL that closed an OSC is not a bell")
    v.feed(b"\x1b]777;notify;cargo;done\x1b\\")
    check(v.events[0][1] == "notice" and v.events[0][2] == ("cargo", "done"),
          "the two-part notice is understood")
    v.feed(b"\x1b]777;precmd;other\x07")
    check([e[1] for e in v.events] == [], "a 777 that is not a notice says nothing")

    #  Resizing keeps the cursor and grows the history.
    v = V(20, 6)
    v.feed(b"l1\r\nl2\r\nl3\r\nl4\r\nl5\r\nl6\r\ncursor")
    v.resize(20, 4)
    check(v.y <= 3 and v.row_text(v.total - 1).rstrip().endswith("cursor"),
          "shrinking keeps the cursor on screen")

    #  The queries a program asks at birth.
    v = V(20, 4)
    v.feed(b"\x1b[6n")
    check(v.replies == [b"\x1b[1;1R"], "the cursor report is exact")
    v.feed(b"\x1b[c")
    check(v.replies[-1].startswith(b"\x1b[?6"), "the device answer is xterm-like")

    #  Keys, as bytes.
    check(key_bytes("enter", False, False, False, False) == "\r",
          "enter is a return")
    check(key_bytes("enter", False, True, False, False) == "\n",
          "ctrl+enter is a newline")
    check(key_bytes("up", False, False, False, True) == "\x1bOA",
          "up in application mode goes through SS3")
    check(key_bytes("up", False, True, False, False) == "\x1b[1;5A",
          "ctrl+up carries its modifier")
    check(key_bytes("tab", True, False, False, False) == "\x1b[Z",
          "shift+tab is the back-tab")
    check(key_bytes("f5", False, False, False, False) == "\x1b[15~", "F5 is 15")

    #  Mouse, both dialects.
    check(mouse_bytes("pulsar", "izquierdo", 3, 5, False, False, False, True)
          == "\x1b[<0;3;5M", "SGR press is exact")
    check(mouse_bytes("soltar", "derecho", 3, 5, False, False, False, True)
          == "\x1b[<2;3;5m", "SGR release ends with m")
    check(mouse_bytes("pulsar", "izquierdo", 1, 1, False, False, False, False)
          == b"\x1b[M !!", "the old dialect still encodes")

    #  The tint, the theme colors, the password shapes.
    check(tinted_background((0, 0, 0), (255, 255, 255)) == (46, 46, 46),
          "the tint mixes at the house strength")
    check(hex_color("#ff30d158") == "#30d158",
          "Qt's alpha-first hex is read as rgb")
    check(tint_color("  Ámbar ") == (0xFF, 0x9F, 0x0A)
          and tint_color("#101820") == (0x10, 0x18, 0x20)
          and tint_color("morado claro") is None,
          "tint names and hand-written hex both work")
    check(asks_for_password("user@host's password: ")
          and not asks_for_password("[sudo] password for rukh: "),
          "the password question is the LAST thing, and sudo's is not it")
    check(asks_about_fingerprint(
        "The authenticity of host 'x' ... (yes/no/[fingerprint])?  "),
        "the fingerprint question ends in ? and says (yes/no")

    #  Color 256's cube and ramp.
    check(color_256(16) == "#000000" and color_256(196) == "#ff0000"
          and color_256(232) == "#080808", "the 256 palette resolves")

    #  Blocks end to end: marks become blocks, folding summarizes,
    #  the frame carries their rows.
    v = V(20, 8)

    class Fake(Island):
        def __init__(self, vt):
            self.vt = vt
            self.blocks = []
            self.command = ""
            self.tint_name = ""
            self.background_now = "#000000"
            self.settings = Settings()
            self.theme = Theme()
            self.job = None
            self.pending_password = None
            self.password_tail = ""
            self.shell_pid = 0
            self.note_child = None
            self.note_fd = None

    fake = Fake(v)

    def drain():
        for _, kind, value in v.events:
            fake._event(kind, value)

    v.feed(b"$ \x1b]633;E;echo hola\x07\x1b]133;C\x07")
    drain()
    v.feed(b"hola\r\nhola\r\nhola\r\n\x1b]133;D;0\x07$ ")
    drain()
    check(fake.blocks and fake.blocks[-1]["estado"] == "bien",
          "a finished block is recorded with its outcome")
    fake.blocks[-1]["plegado"] = True
    frame = fake.frame()
    check(frame["resumidas"]
          and "echo hola" in frame["filas"][frame["resumidas"][0]][0]["t"],
          "a folded block shows its command and its size")
    check(frame["filas"][frame["resumidas"][0]][0]["c"] == 1,
          "the summary starts at the first column")

    #  text_of cuts the way a selection expects.
    v = V(20, 6)
    v.feed(b"uno\r\ndos tres\r\ncuatro")
    cutter = Fake(v)
    check(Island.text_of(cutter, 0, 1, 2, 6) == "no\ndos tr",
          "the first and last lines are cut by column")
    check(Island.text_of(cutter, 1, 1, 2, 4) == "os ",
          "a single line is cut from both ends")

    if failures:
        for name in failures:
            print("FAIL: %s" % name)
        sys.exit(1)
    print("island: all green")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    elif "--note" in sys.argv:
        run_as_note_child()
    else:
        Island().run()
