#  A screen that behaves like a terminal.
#
#  This is the emulator k4term ships compiled — Ghostty's VT core —
#  written small enough to carry: the island session needs a grid,
#  colors, the usual modes and a scrollback, and it needs to be asked
#  for its contents as runs of styled text. Nothing here knows about
#  PTYs, processes or the bar; `island.py` drives it and talks.
#
#  Why hand-written instead of a library: the runtime is the host's
#  plain python3, with no pip site-packages to lean on, and the
#  protocol we serve is ours — a dump of runs with their columns, not
#  a framebuffer. The classic set (what zsh, vim, htop and the agent
#  consoles emit) is well specified and well trodden; what is NOT
#  implemented is named at the bottom so nobody discovers it by
#  surprise.
#
#  Coordinates: the grid is `rows` lines by `cols` columns, cursor at
#  (x, y), both 0-based. History is a list of lines ABOVE the grid,
#  so a line's absolute number is len(history) + y — the coordinate
#  every marker, block and selection travels as, because it survives
#  the screen scrolling underneath.
#
#  Colors are kept UNRESOLVED on purpose: a cell remembers «color 3»,
#  not «#cd3133», because the palette can be redefined after the cell
#  was written and a terminal repaints what it already showed.
#  Resolution happens once, at dump time.

import base64
import codecs
import unicodedata

#  Flag bits, as the bar's view reads them (`n` in every run):
#  0x01 dim, 0x02 bold, 0x04 italic, 0x08 underline, 0x10 reverse
#  (resolved away before it leaves here), 0x40 strikeout.
DIM, BOLD, ITALIC, UNDERLINE, REVERSED, STRIKETHROUGH = 1, 2, 4, 8, 16, 64

#  The sixteen of always. xterm's, because they are the ones thirty
#  years of color scripts were tuned against; the house tints the
#  foreground and the background over them, not them.
BASE_PALETTE = [
    "#000000", "#cd3133", "#0dbc79", "#e5e510",
    "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
    "#666666", "#f14c4c", "#23d18b", "#f5f543",
    "#3b8eea", "#d670d6", "#29b8db", "#ffffff",
]

#  DEC's special graphics, the drawing alphabet of every TUI since
#  1978. htop's bars and vim's splits are these characters; without
#  the table they arrive as `q` and `x` and the screen falls apart.
GRAPHICS_CHARSET = {
    "j": "┘", "k": "┐", "l": "┌", "m": "└", "n": "┼",
    "q": "─", "t": "├", "u": "┤", "v": "┴", "w": "┬", "x": "│",
    "a": "▒", "`": "◆", "f": "°", "g": "±", "o": "⎺", "p": "⎻",
    "r": "⎼", "s": "⎽", "~": "·", "0": "▮",
}

BLANK = (" ", None, None, 0, None)


def _hex(r, g, b):
    return "#{:02x}{:02x}{:02x}".format(r, g, b)


def color_256(n):
    #  The palette half, the cube and the gray ramp. Live and not
    #  cached so a redefined 0-15 is honored everywhere at once.
    if n < 16:
        return BASE_PALETTE[n]
    if n < 232:
        values = (0, 95, 135, 175, 215, 255)
        n -= 16
        return _hex(values[(n // 36) % 6], values[(n // 6) % 6], values[n % 6])
    return _hex(8 + (n - 232) * 10, 8 + (n - 232) * 10, 8 + (n - 232) * 10)


def _from_rgb(text):
    #  `rgb:xx/xx/xx`, with one to four hex digits per component.
    if not text.startswith("rgb:"):
        return None
    parts = text[4:].split("/")
    if len(parts) != 3:
        return None
    values = []
    for p in parts:
        if len(p) not in (1, 2, 4) or not all(c in "0123456789abcdefABCDEF" for c in p):
            return None
        values.append(int((p * 2)[:2] if len(p) == 1 else p[:2], 16))
    return _hex(*values)


class VT:
    def __init__(self, cols, rows, history_limit=10000):
        #  No minimums here: the protocol layer clamps what the bar
        #  asks for; the core takes sizes as told, so tests can use
        #  tiny grids.
        self.cols = cols
        self.rows = rows
        self.history_limit = max(0, history_limit)

        #  The screen, the alternate one, the history between them.
        self.grid = [self._blank_row() for _ in range(self.rows)]
        self.grid_alt = [self._blank_row() for _ in range(self.rows)]
        self.history = []
        self.history_start = 0
        self.event_sink = None

        #  Cursor and the pen it writes with.
        self.x = 0
        self.y = 0
        self._fg = None          # None | 0-255 | "#rrggbb"
        self._bg = None
        self._flags = 0
        self._link = None
        self._wrap_pending = False
        self._last_char = " "

        #  Modes. Defaults are xterm's, because programs assume them.
        self.autowrap = True
        self.origin_mode = False
        self.insert_mode = False
        self.cursor_visible = True
        self.app_cursor = False
        self.bracketed_paste = False
        self.mouse_mode = 0       # 0 | 9 | 1000 | 1002 | 1003
        self.mouse_sgr = False
        self.alt_screen = False

        #  Scroll margins, 0-based inclusive; None means everything.
        self.margin_top = None
        self.margin_bottom = None

        #  Tab stops: explicit ones over the implicit every-eight.
        self.tabs = set(range(8, cols, 8))

        #  Charsets: G0..G3 names and which one is shifted in.
        self._charsets = ["B", "B", "B", "B"]
        self._shift = 0
        self._saved = None
        self._primary_saved = None
        self._charset_slot = 0

        #  The palette the cells point at, a copy so OSC 4 can move it.
        self.palette = list(BASE_PALETTE)
        self.default_fg = "#ffffff"
        self.default_bg = "#000000"

        #  How programs name themselves (OSC 0/2), and how the cursor
        #  looks, because vim says its mode with it (DECSCUSR).
        self.title = ""
        self.cursor_shape = "block"
        self.cursor_blinks = True

        #  Replies owed to the program (DSR, DA, color queries...).
        #  Bytes and ordered: whoever asks is waiting, and the answer
        #  must go out in arrival order.
        self.replies = []

        #  Viewport: how many lines above the bottom we are looking.
        #  0 is «follow the output»; anything else keeps the content
        #  still while the screen moves on below.
        self.scrolled = 0

        #  Stream events: (byte index, kind, value). The index is
        #  where the sequence ENDED, so a marker lands where it
        #  happened and not where the burst ended.
        self.events = []

        #  Parser state.
        self._state = "ground"    # ground|esc|charset|csi|osc|osc_esc|dcs|dcs_esc
        self._csi_params = b""
        self._csi_inter = b""
        self._osc = b""
        self._decoder = codecs.getincrementaldecoder("utf-8")("replace")

    # ── construction helpers ─────────────────────────────────────

    def _blank_row(self, width=None):
        return [BLANK] * (width or self.cols)

    def _blank_with_bg(self):
        #  Erase fills with the CURRENT background — background color
        #  erase, what makes a red status line stay red when the
        #  program clears over it.
        return (" ", self._fg, self._bg, 0, None)

    # ── the geometry the protocol asks for ───────────────────────

    @property
    def top(self):
        #  The first absolute line the viewport shows.
        return self.screen_start - (0 if self.alt_screen else self.scrolled)

    @property
    def screen_start(self):
        return self.history_start + len(self.history)

    @property
    def total(self):
        return self.screen_start + self.rows

    def cursor_abs_row(self):
        return self.screen_start + self.y

    def row(self, abs_row):
        if abs_row < self.history_start or abs_row >= self.total:
            return None
        if abs_row < self.screen_start:
            return None if self.alt_screen else self.history[abs_row - self.history_start]
        return self.grid[abs_row - self.screen_start]

    def row_text(self, abs_row):
        line = self.row(abs_row)
        if line is None:
            return ""
        return "".join(unicodedata.normalize("NFC", c[0]) for c in line)

    def row_slice(self, abs_row, start=0, end=None):
        line = self.row(abs_row)
        if line is None:
            return ""
        return "".join(unicodedata.normalize("NFC", c[0]) for c in line[start:end])

    def scroll_viewport(self, delta):
        #  With no history there is nowhere to go; the alt screen has
        #  none by design and the grid is what it is.
        if self.alt_screen:
            self.scrolled = 0
            return
        self.scrolled = max(0, min(len(self.history), self.scrolled - delta))

    def scroll_viewport_edge(self, top=True):
        if self.alt_screen:
            return
        self.scrolled = len(self.history) if top else 0

    @property
    def mouse_active(self):
        return self.mouse_mode != 0

    # ── dump: a row as runs ──────────────────────────────────────

    def _color(self, c, background=False):
        if c is None:
            return self.default_bg if background else self.default_fg
        if isinstance(c, int):
            c = max(0, min(255, c))
            return self.palette[c] if c < 16 else color_256(c)
        return c

    def row_runs(self, abs_row):
        #  Runs of same-style cells with the COLUMN they start at
        #  (1-based) — what keeps cursor and text aligned when a
        #  glyph is not one cell wide.
        line = self.row(abs_row)
        if line is None:
            return []
        runs = []
        i = 0
        n = len(line)
        while i < n:
            text, fg, bg, flags, link = line[i]
            if text == "":
                i += 1
                continue
            fg, bg = self._color(fg), self._color(bg, True)
            if flags & REVERSED:
                fg, bg = bg, fg
            flags &= ~REVERSED
            letters = [unicodedata.normalize("NFC", text)]
            j = i + (2 if i + 1 < n and line[i + 1][0] == "" else 1)
            # Non-ASCII graphemes stand alone. Their column and explicit
            # width keep Qt's shaping and UTF-16 string length out of the
            # terminal's cell arithmetic.
            while j < n:
                t2, fg2, bg2, f2, l2 = line[j]
                if not text.isascii() or not t2.isascii() or not t2:
                    break
                fg2, bg2 = self._color(fg2), self._color(bg2, True)
                if f2 & REVERSED:
                    fg2, bg2 = bg2, fg2
                if (fg2, bg2, f2 & ~REVERSED, l2) != (fg, bg, flags, link):
                    break
                letters.append(t2)
                j += 1
            run = {"c": i + 1, "t": "".join(letters),
                   "f": fg, "b": bg, "n": flags, "width": j - i}
            if link:
                run["u"] = link
            runs.append(run)
            i = j
        #  The tail that says nothing —spaces over the usual
        #  background— is dropped: in a terminal screen that is most
        #  of it, and a row's real extent is what decides how tall
        #  the island grows. Colored spaces STAY: they are vim's
        #  status line and a selection, and dropping them would lie.
        while (runs and runs[-1]["t"].strip() == ""
               and runs[-1]["b"] == self.default_bg
               and "u" not in runs[-1]):
            runs.pop()
        return runs

    # ── writing ──────────────────────────────────────────────────

    def _region(self):
        top = self.margin_top if self.margin_top is not None else 0
        bottom = self.margin_bottom if self.margin_bottom is not None else self.rows - 1
        return (top, bottom)

    def _scroll_up(self, count=1):
        #  Push the top of the scroll region up. Only a full-screen
        #  region feeds the history: a TUI scrolling its own box must
        #  not fill the scrollback with boxes.
        top, bottom = self._region()
        for _ in range(min(count, bottom - top + 1)):
            if top == 0 and bottom == self.rows - 1 and not self.alt_screen:
                self._remember(self.grid[top])
                #  Whoever is reading from up there stays anchored to
                #  the content — the same absolute top, while the
                #  screen grows below. And whoever is at the bottom
                #  STAYS at the bottom: following the output is the
                #  default state, and this used to move it up one line
                #  per line printed, until the view froze on the top
                #  of history and no output was ever seen again.
                if self.scrolled > 0:
                    self.scrolled = min(self.scrolled + 1, len(self.history))
            del self.grid[top]
            self.grid.insert(bottom, [self._blank_with_bg()] * self.cols)

    def _remember(self, row):
        self.history.append(row)
        self.trim_history()

    def trim_history(self):
        excess = max(0, len(self.history) - self.history_limit)
        if excess:
            del self.history[:excess]
            self.history_start += excess
        self.scrolled = min(self.scrolled, len(self.history))

    def _scroll_down(self, count=1):
        top, bottom = self._region()
        for _ in range(min(count, bottom - top + 1)):
            del self.grid[bottom]
            self.grid.insert(top, [self._blank_with_bg()] * self.cols)

    def _linefeed(self):
        #  One line down, scrolling when at the region's bottom.
        top, bottom = self._region()
        if self.y == bottom:
            self._scroll_up(1)
        elif self.y < self.rows - 1:
            self.y += 1

    def _char_width(self, ch):
        #  East Asian wide/full take two cells. The Nerd Font's
        #  private-use glyphs are ONE: prompts lay them out as one
        #  and the bar measures them as one.
        if 0xE000 <= ord(ch) <= 0xF8FF:
            return 1
        return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1

    def put_char(self, ch):
        if unicodedata.combining(ch) or ch in ("\u200b", "\u200d", "\ufe0f"):
            #  A mark that combines takes no cell: it joins the one
            #  before it. With nowhere to join, it is dropped — a
            #  combining mark alone is nothing anyone can see.
            if self.x > 0 or (self.x == 0 and self.grid[self.y][0][0] != " "):
                line = self.grid[self.y]
                x = self.x if self._wrap_pending else max(0, self.x - 1)
                if line[x][0] == "" and x > 0:
                    x -= 1
                text, fg, bg, flags, link = line[x]
                line[x] = (text + ch, fg, bg, flags, link)
            return
        width = self._char_width(ch)
        if width > self.cols:
            return

        if self._wrap_pending:
            if self.autowrap:
                self.x = 0
                self._linefeed()
            self._wrap_pending = False

        if width == 2 and self.x == self.cols - 1:
            #  A wide glyph does not fit the last column: it wraps
            #  whole, leaving an unused cell behind.
            if self.autowrap:
                self.grid[self.y][self.x] = self._blank_with_bg()
                self.x = 0
                self._linefeed()
            else:
                return

        if self.insert_mode:
            line = self.grid[self.y]
            line[self.x + width:] = line[self.x:max(self.x, self.cols - width)]
        # Erasing either half of a wide character clears the other half.
        line = self.grid[self.y]
        if line[self.x][0] == "" and self.x > 0:
            line[self.x - 1] = self._blank_with_bg()
        for pos in range(self.x, min(self.cols, self.x + width)):
            if pos + 1 < self.cols and line[pos + 1][0] == "":
                line[pos + 1] = self._blank_with_bg()
        cell = (ch, self._fg, self._bg, self._flags, self._link)
        self.grid[self.y][self.x] = cell
        if width == 2:
            #  The wide glyph's SECOND cell is written too — a blank
            #  with the same style. Without it the cell kept whatever
            #  was there before, and a dump said the row had one cell
            #  fewer than it paints: text after the glyph landed one
            #  column left of where the terminal put it.
            self.grid[self.y][self.x + 1] = ("", self._fg, self._bg,
                                             self._flags, self._link)
        self._last_char = ch
        self.x += width
        if self.x >= self.cols:
            self.x = self.cols - 1
            if self.autowrap:
                self._wrap_pending = True

    def _print(self, ch):
        if self._charsets[self._shift] == "0" and ch in GRAPHICS_CHARSET:
            ch = GRAPHICS_CHARSET[ch]
        self.put_char(ch)

    def _tab(self):
        target = self.x + 1
        while target < self.cols:
            if target in self.tabs:
                break
            target += 1
        self.x = min(target, self.cols - 1)

    # ── the parser ───────────────────────────────────────────────

    def feed(self, data):
        #  One pass, byte by byte, state between bytes. Escape
        #  sequences are ASCII so they can never be half of a UTF-8
        #  character, and that is what makes this simple loop safe.
        self.events = []
        for i, b in enumerate(data):
            if b in (0x18, 0x1A):
                self._state = "ground"
                continue
            state = self._state
            if state == "ground":
                self._ground(b, i)
            elif state == "esc":
                self._esc(b)
            elif state == "charset":
                self._charsets[self._charset_slot] = chr(b)
                self._state = "ground"
            elif state == "csi":
                self._csi_byte(b)
            elif state == "osc":
                self._osc_byte(b, i)
            elif state == "osc_esc":
                if b == 0x5C:  #  ESC \ closes the OSC
                    self._osc_done(i)
                    self._state = "ground"
                else:
                    #  A stray escape inside the body: part of it.
                    self._osc += b"\x1b" + bytes([b])
                    self._state = "osc"
            elif state == "dcs":
                if b == 0x1B:
                    self._state = "dcs_esc"
            elif state == "dcs_esc":
                #  Whatever a DCS said, it is swallowed whole: sixel
                #  and kitty's keyboard negotiation both end at ST,
                #  unheeded. Not claiming what we do not draw.
                self._state = "ground" if b == 0x5C else "dcs"

    def _emit(self, index, kind, value):
        self.events.append((index, kind, value))
        if self.event_sink:
            self.event_sink(kind, value)

    def _ground(self, b, i):
        if b == 0x1B:
            self._state = "esc"
            for ch in self._decoder.decode(b"", final=True):
                self._print(ch)
            self._decoder.reset()
            return
        if b == 0x07:
            self._emit(i + 1, "bell", None)
            return
        if b < 0x20 or b == 0x7F:
            if b in (0x0A, 0x0B, 0x0C):
                self._wrap_pending = False
                self._linefeed()
            elif b == 0x0D:
                self.x = 0
                self._wrap_pending = False
            elif b == 0x08:
                if self.x > 0:
                    self.x -= 1
                self._wrap_pending = False
            elif b == 0x09:
                self._tab()
            elif b == 0x0E:
                self._shift = 1
            elif b == 0x0F:
                self._shift = 0
            return
        for ch in self._decoder.decode(bytes([b])):
            self._print(ch)

    def _esc(self, b):
        self._state = "ground"
        c = chr(b)
        if c == "[":
            self._state = "csi"
            self._csi_params = b""
            self._csi_inter = b""
        elif c == "]":
            self._state = "osc"
            self._osc = b""
        elif c in ("P", "X", "^", "_"):
            self._state = "dcs"
        elif c in "()*+":
            self._charset_slot = (b - 0x28) & 3
            self._state = "charset"
        elif c == "7":
            self._save_cursor()
        elif c == "8":
            self._restore_cursor()
        elif c == "D":
            self._linefeed()
        elif c == "M":
            top, _ = self._region()
            if self.y == top:
                self._scroll_down(1)
            elif self.y > 0:
                self.y -= 1
        elif c == "E":
            self.x = 0
            self._linefeed()
        elif c == "H":
            self.tabs.add(self.x)
        elif c == "c":
            self._full_reset()

    def _csi_byte(self, b):
        if b == 0x1B:
            self._state = "esc"
            return
        if len(self._csi_params) + len(self._csi_inter) > 1024:
            self._state = "ground"
            return
        if 0x30 <= b <= 0x3F:
            self._csi_params += bytes([b])
            return
        if 0x20 <= b <= 0x2F:
            self._csi_inter += bytes([b])
            return
        self._state = "ground"
        self._csi(chr(b))

    def _csi(self, final):
        params, private = self._parse_params()
        n = params[0] if params else 0
        if final == "h":
            self._set_modes(params, private, True)
        elif final == "l":
            self._set_modes(params, private, False)
        elif final == "m" and not private:
            self._sgr(self._sgr_params())
        elif final == "A":
            top, bottom = self._region()
            self.y = max(top if top <= self.y <= bottom else 0, self.y - max(1, n))
            self._wrap_pending = False
        elif final in ("B", "e"):
            top, bottom = self._region()
            self.y = min(bottom if top <= self.y <= bottom else self.rows - 1,
                         self.y + max(1, n))
            self._wrap_pending = False
        elif final in ("C", "a"):
            self.x = min(self.cols - 1, self.x + max(1, n))
            self._wrap_pending = False
        elif final == "D":
            self.x = max(0, self.x - max(1, n))
            self._wrap_pending = False
        elif final == "E":
            self.y = min(self._region()[1], self.y + max(1, n))
            self.x = 0
        elif final == "F":
            self.y = max(self._region()[0], self.y - max(1, n))
            self.x = 0
        elif final in ("G", "`"):
            self.x = min(self.cols - 1, max(0, n - 1))
            self._wrap_pending = False
        elif final == "d":
            self.y = self._absolute_row_of(n)
            self._wrap_pending = False
        elif final in ("H", "f"):
            self._goto(n, params[1] if len(params) > 1 else 1)
        elif final == "I":
            for _ in range(max(1, n)):
                self._tab()
        elif final == "Z":
            for _ in range(min(max(1, n), self.cols)):
                target = self.x - 1
                while target > 0 and target not in self.tabs:
                    target -= 1
                self.x = max(0, target)
        elif final == "g":
            if n == 0:
                self.tabs.discard(self.x)
            elif n == 3:
                self.tabs.clear()
        elif final == "J":
            self._erase_display(n)
        elif final == "K":
            self._erase_line(n)
        elif final == "L":
            self._insert_lines(max(1, n))
        elif final == "M":
            self._delete_lines(max(1, n))
        elif final == "@":
            self._insert_cells(max(1, n))
        elif final == "P":
            self._delete_cells(max(1, n))
        elif final == "X":
            line = self.grid[self.y]
            for i in range(self.x, min(self.cols, self.x + max(1, n))):
                line[i] = self._blank_with_bg()
        elif final == "S":
            self._scroll_up(max(1, n))
        elif final == "T":
            self._scroll_down(max(1, n))
        elif final == "b":
            for _ in range(min(max(1, n), self.rows * self.cols)):
                self.put_char(self._last_char)
        elif final == "r":
            self._set_margins(params)
            self._goto(1, 1)
        elif final == "s":
            self._save_cursor()
        elif final == "u" and private == "?":
            self.replies.append(b"\x1b[?0u")
        elif final == "u" and not private:
            self._restore_cursor()
        elif final == "n":
            self._report(n)
        elif final == "c":
            if private == ">":
                self.replies.append(b"\x1b[>41;0;0c")
            elif not private:
                #  VT220-with-modern-features: what everything from
                #  vim to ncurses probes for and branches on.
                self.replies.append(b"\x1b[?62;22c")
        elif final == "q":
            #  DECSCUSR, with a space intermediate. The names are the
            #  wire protocol's (Spanish): the bar's view matches
            #  «bloque», «subrayado», «barra» — what shape the program
            #  asks for is how vim says its mode without writing it.
            if self._csi_inter == b" ":
                forma = {0: "bloque", 1: "bloque", 2: "bloque",
                         3: "subrayado", 4: "subrayado",
                         5: "barra", 6: "barra"}.get(n)
                if forma:
                    self.cursor_shape = forma
                    self.cursor_blinks = n in (0, 1, 3, 5)
        elif final == "t":
            if n == 18:
                self.replies.append(
                    ("\x1b[8;%d;%dt" % (self.rows, self.cols)).encode())

    def _parse_params(self):
        #  SGR's colon subparameters (38:2::r:g:b, the modern
        #  truecolor) are flattened to semicolons: to us they mean
        #  the same and the parser stays one shape. The private
        #  prefix (? > < =) rides along separately.
        raw = self._csi_params.decode("ascii", "replace")
        private = ""
        if raw[:1] in ("?", ">", "<", "="):
            private = raw[0]
            raw = raw[1:]
        out = []
        for piece in raw.replace(":", ";").split(";"):
            try:
                out.append(int(piece or "0"))
            except ValueError:
                out.append(0)
        return out or [0], private

    def _sgr_params(self):
        # Preserve colon groups before flattening. A following semicolon
        # attribute is never a colorspace slot in an RGB specification.
        params = []
        for group in self._csi_params.decode("ascii", "replace").split(";"):
            try:
                values = [int(v or "0") for v in group.split(":")]
            except ValueError:
                continue
            if len(values) >= 6 and values[0] in (38, 48, 58) and values[1] == 2:
                values = values[:2] + values[3:6]
            params.extend(values)
        return params or [0]

    def _absolute_row_of(self, n):
        if self.origin_mode:
            top, bottom = self._region()
            return min(bottom, top + max(1, n) - 1)
        return min(self.rows - 1, max(0, n - 1))

    def _goto(self, row, col):
        if self.origin_mode:
            top, bottom = self._region()
            self.y = min(bottom, top + max(1, row) - 1)
        else:
            self.y = min(self.rows - 1, max(0, row - 1))
        self.x = min(self.cols - 1, max(0, col - 1))
        self._wrap_pending = False

    def _set_margins(self, params):
        top = max(1, params[0]) - 1
        bottom = (params[1] if len(params) > 1 and params[1] else self.rows) - 1
        if 0 <= top < bottom < self.rows:
            full = top == 0 and bottom == self.rows - 1
            self.margin_top = None if full else top
            self.margin_bottom = None if full else bottom
            if not (top <= self.y <= bottom):
                self._goto(1, 1)

    def _sgr(self, params):
        i = 0
        while i < len(params):
            p = params[i]
            if p == 0:
                self._fg = self._bg = None
                self._flags = 0
            elif p == 1:
                self._flags |= BOLD
            elif p == 2:
                self._flags |= DIM
            elif p == 3:
                self._flags |= ITALIC
            elif p == 4:
                self._flags |= UNDERLINE
            elif p == 7:
                self._flags |= REVERSED
            elif p == 9:
                self._flags |= STRIKETHROUGH
            elif p == 21:
                self._flags |= UNDERLINE
            elif p == 22:
                self._flags &= ~(BOLD | DIM)
            elif p == 23:
                self._flags &= ~ITALIC
            elif p == 24:
                self._flags &= ~UNDERLINE
            elif p == 27:
                self._flags &= ~REVERSED
            elif p == 29:
                self._flags &= ~STRIKETHROUGH
            elif 30 <= p <= 37 or 90 <= p <= 97:
                self._fg = p - 30 if p < 90 else p - 90 + 8
            elif p == 39:
                self._fg = None
            elif 40 <= p <= 47 or 100 <= p <= 107:
                self._bg = p - 40 if p < 100 else p - 100 + 8
            elif p == 49:
                self._bg = None
            elif p in (38, 48):
                #  The colon form flattens with an empty colorspace
                #  slot between the 2 and the numbers; the semicolon
                #  form never has one. Told apart by counting. The
                #  skip consumes the WHOLE group — leaving one number
                #  behind made it land as a fresh SGR and repaint the
                #  very thing being set.
                if i + 1 < len(params) and params[i + 1] == 5 and i + 2 < len(params):
                    color = max(0, min(255, params[i + 2]))
                    i += 2
                elif i + 1 < len(params) and params[i + 1] == 2:
                    values = params[i + 2:i + 5]
                    i += 4
                    color = _hex(*(max(0, min(255, v)) for v in values)) \
                        if len(values) == 3 else None
                else:
                    color = None
                if p == 38:
                    self._fg = color
                else:
                    self._bg = color
            elif p == 58:
                #  Underline color: parsed so the sequence is eaten,
                #  painted with the underline that already exists.
                if i + 1 < len(params) and params[i + 1] == 5:
                    i += 2
                elif i + 1 < len(params) and params[i + 1] == 2:
                    i += 4
            i += 1

    def _set_modes(self, params, private, on):
        if private == "?":
            for p in params:
                if p == 1:
                    self.app_cursor = on
                elif p == 6:
                    self.origin_mode = on
                    if on:
                        self._goto(1, 1)
                elif p == 7:
                    self.autowrap = on
                    if not on:
                        self._wrap_pending = False
                elif p == 4:
                    self.insert_mode = on
                elif p == 25:
                    self.cursor_visible = on
                elif p in (9, 1000, 1002, 1003):
                    self.mouse_mode = p if on else 0
                elif p == 1006:
                    self.mouse_sgr = on
                elif p == 2004:
                    self.bracketed_paste = on
                elif p in (47, 1047):
                    self._alt_screen(on, clear_on_leave=(p == 1047))
                elif p == 1048:
                    if on:
                        self._save_cursor()
                    else:
                        self._restore_cursor()
                elif p == 1049:
                    self._alt_screen(on, save_cursor=True)
            return
        if private == "":
            for p in params:
                if p == 4:
                    self.insert_mode = on

    def _alt_screen(self, enter, clear_on_leave=False, save_cursor=False):
        if enter == self.alt_screen:
            return
        if enter:
            if save_cursor:
                self._save_cursor()
                self._primary_saved = self._saved
            self.grid, self.grid_alt = self.grid_alt, self.grid
            if save_cursor:
                self.grid[:] = [self._blank_row() for _ in range(self.rows)]
            self.alt_screen = True
            self.scrolled = 0
            self.x = self.y = 0
        else:
            if clear_on_leave:
                self.grid[:] = [self._blank_row() for _ in range(self.rows)]
            self.grid, self.grid_alt = self.grid_alt, self.grid
            self.alt_screen = False
            self.scrolled = 0
            if save_cursor:
                self._saved = self._primary_saved
                self._restore_cursor()
        self.margin_top = self.margin_bottom = None
        self._wrap_pending = False

    def _save_cursor(self):
        self._saved = (self.x, self.y, self._fg, self._bg, self._flags,
                       self._link, self.origin_mode, tuple(self._charsets),
                       self._shift)

    def _restore_cursor(self):
        if self._saved:
            (self.x, self.y, self._fg, self._bg, self._flags,
             self._link, self.origin_mode, charsets, self._shift) = self._saved
            self._charsets = list(charsets)
            self.x = max(0, min(self.cols - 1, self.x))
            self.y = max(0, min(self.rows - 1, self.y))
            self._wrap_pending = False

    def _full_reset(self):
        start, sink = self.total, self.event_sink
        fg, bg = self.default_fg, self.default_bg
        self.__init__(self.cols, self.rows, self.history_limit)
        self.history_start, self.event_sink = start, sink
        self.default_fg, self.default_bg = fg, bg
        self._emit(0, "reset", None)

    def _erase_display(self, mode):
        if mode == 0:
            self._erase_line(0)
            for r in range(self.y + 1, self.rows):
                self.grid[r] = [self._blank_with_bg()] * self.cols
        elif mode == 1:
            self._erase_line(1)
            for r in range(0, self.y):
                self.grid[r] = [self._blank_with_bg()] * self.cols
        elif mode == 2:
            for r in range(self.rows):
                self.grid[r] = [self._blank_with_bg()] * self.cols
        elif mode == 3:
            #  xterm's «erase saved lines»: the scrollback and only
            #  it, which is what `clear` asks the driver to ask.
            self.history_start = self.screen_start
            self.history = []
            self.scrolled = 0

    def _erase_line(self, mode):
        line = self.grid[self.y]
        blank = self._blank_with_bg()
        if mode == 0:
            for i in range(self.x, self.cols):
                line[i] = blank
        elif mode == 1:
            for i in range(0, min(self.x + 1, self.cols)):
                line[i] = blank
        elif mode == 2:
            self.grid[self.y] = [blank] * self.cols

    def _insert_lines(self, count):
        top, bottom = self._region()
        if not (top <= self.y <= bottom):
            return
        count = min(count, bottom + 1 - self.y)
        del self.grid[bottom + 1 - count:bottom + 1]
        self.grid[self.y:self.y] = [self._blank_row() for _ in range(count)]
        self.x = 0

    def _delete_lines(self, count):
        top, bottom = self._region()
        if not (top <= self.y <= bottom):
            return
        count = min(count, bottom + 1 - self.y)
        del self.grid[self.y:self.y + count]
        self.grid[bottom + 1 - count:bottom + 1 - count] = \
            [self._blank_row() for _ in range(count)]
        self.x = 0

    def _insert_cells(self, count):
        line = self.grid[self.y]
        count = min(count, self.cols - self.x)
        line[self.x + count:] = line[self.x:self.cols - count]
        for i in range(self.x, self.x + count):
            line[i] = self._blank_with_bg()

    def _delete_cells(self, count):
        line = self.grid[self.y]
        count = min(count, self.cols - self.x)
        line[self.x:self.cols - count] = line[self.x + count:]
        for i in range(self.cols - count, self.cols):
            line[i] = self._blank_with_bg()

    def _report(self, which):
        if which == 5:
            self.replies.append(b"\x1b[0n")
        elif which == 6:
            top, _ = self._region()
            row = self.y - top + 1 if self.origin_mode else self.y + 1
            self.replies.append(("\x1b[%d;%dR" % (row, self.x + 1)).encode())

    # ── OSC ──────────────────────────────────────────────────────

    def _osc_byte(self, b, i):
        if b == 0x07:
            self._osc_done(i)
            self._state = "ground"
        elif b == 0x1B:
            self._state = "osc_esc"
        elif b == 0x9C:
            self._osc_done(i)
            self._state = "ground"
        elif len(self._osc) < 8192:
            self._osc += bytes([b])

    def _osc_done(self, i):
        text = self._osc.decode("utf-8", "replace")
        if ";" not in text:
            return
        code, rest = text.split(";", 1)
        try:
            if code in ("0", "2"):
                self.title = rest
                self._emit(i + 1, "title", rest)
            elif code == "4":
                self._osc_palette(rest)
            elif code == "8":
                #  The link behind the next words; empty closes it.
                #  The body is `params;uri`, and params may be empty.
                if ";" in rest:
                    _, uri = rest.split(";", 1)
                else:
                    uri = rest
                self._link = uri or None
            elif code in ("10", "11"):
                self._osc_default_color(code, rest)
            elif code == "52":
                self._osc_clipboard(rest, i)
            elif code == "133":
                self._osc_prompt_mark(rest, i)
            elif code == "633":
                if rest.startswith("E;"):
                    self._emit(i + 1, "command", rest[2:])
            elif code == "9":
                if rest:
                    self._emit(i + 1, "notice", ("k4term", rest))
            elif code == "777":
                if rest.startswith("notify;"):
                    body = rest[7:]
                    if ";" in body:
                        title, text_body = body.split(";", 1)
                    else:
                        title, text_body = body, ""
                    if title:
                        self._emit(i + 1, "notice", (title, text_body))
        except Exception:
            #  An OSC we half-understood is dropped whole: guessing at
            #  a half-parse leaves the screen in a state no one sent.
            pass

    def _osc_palette(self, rest):
        pieces = rest.split(";")
        j = 0
        while j + 1 < len(pieces):
            try:
                index = int(pieces[j])
            except ValueError:
                j += 1
                continue
            spec = pieces[j + 1]
            j += 2
            if not 0 <= index <= 255:
                continue
            if spec == "?":
                color = (self.palette[index] if index < 16
                         else color_256(index)).lstrip("#")
                self.replies.append(
                    ("\x1b]4;%d;rgb:%s/%s/%s\x1b\\"
                     % (index, color[0:2], color[2:4], color[4:6])).encode())
                continue
            rgb = _from_rgb(spec)
            if rgb and 0 <= index < 16:
                self.palette[index] = rgb

    def _osc_default_color(self, code, rest):
        if rest == "?":
            which = self.default_fg if code == "10" else self.default_bg
            c = which.lstrip("#")
            self.replies.append(
                ("\x1b]%s;rgb:%s/%s/%s\x1b\\"
                 % (code, c[0:2], c[2:4], c[4:6])).encode())
            return
        rgb = _from_rgb(rest)
        if rgb:
            if code == "10":
                self.default_fg = rgb
            else:
                self.default_bg = rgb

    def _osc_clipboard(self, rest, i):
        if ";" not in rest:
            return
        _, payload = rest.split(";", 1)
        if not payload or payload == "?":
            #  Reading the clipboard from here is nobody's business;
            #  an empty answer and out.
            self.replies.append(b"\x1b]52;;\x1b\\")
            return
        try:
            text = base64.b64decode(payload).decode("utf-8", "replace")
        except Exception:
            return
        self._emit(i + 1, "clipboard", text)

    def _osc_prompt_mark(self, rest, i):
        #  The semantic prompt, iTerm2's convention half the shells
        #  speak: C is «the command runs», D;<code> is «it ended».
        if rest == "A":
            self._emit(i + 1, "prompt", None)
        elif rest == "C":
            self._emit(i + 1, "start", None)
        elif rest == "D" or rest.startswith("D;"):
            code = rest[2:] if rest.startswith("D;") else ""
            try:
                status = int(code.strip() or "0")
            except ValueError:
                status = 0
            self._emit(i + 1, "finish", status)

    # ── resizing ─────────────────────────────────────────────────

    def resize(self, cols, rows):
        cols, rows = max(1, cols), max(1, rows)
        if cols == self.cols and rows == self.rows:
            return
        #  Shrinking keeps the cursor on screen by handing lines to
        #  the history — what one sees pulling a window's bottom up
        #  over a running command.
        while self.rows > rows and self.y >= rows and not self.alt_screen:
            self._remember(self.grid[0])
            del self.grid[0]
            self.y -= 1
        for grid in (self.grid, self.grid_alt):
            del grid[rows:]
            while len(grid) < rows:
                grid.append([BLANK] * cols)
            for r, line in enumerate(grid):
                cropped = len(line) > cols and line[cols][0] == ""
                grid[r] = line[:cols] + [BLANK] * max(0, cols - len(line))
                if cropped:
                    grid[r][-1] = BLANK
        self.tabs.update(range(((self.cols + 7) // 8) * 8, cols, 8))
        self.rows = rows
        self.cols = cols
        self.y = min(self.y, rows - 1)
        self.x = min(self.x, cols - 1)
        self.margin_top = self.margin_bottom = None
        self._wrap_pending = False
        self.scrolled = min(self.scrolled, len(self.history))


#  Deliberately not implemented, so it is said once and in writing:
#  kitty's graphics and progressive keyboard (the queries are
#  answered «none», and programs fall back to the classic encoding),
#  sixel, DECRQSS replies, focus reporting, and reflow on resize —
#  rows are cut, never rewrapped.
