# Island terminal

`k4.term island` toggles the terminal view. Hiding the view preserves its
sessions and running jobs. Escape is sent to the terminal application.
Closing a tab, exiting its shell, disabling the plugin, or stopping the bar
ends the session. Sessions do not survive a bar restart.

The plugin uses `k4term-isla` when available and otherwise starts the bundled
Python PTY backend. The Nix package includes Python. Each session retains its
original backend even when binaries are installed or removed. Moving a
session to a window requires a native session and the k4term window binary.

## Keyboard and IPC

| Action | Shortcut or IPC verb on `k4.term` |
|---|---|
| Show/hide the view | `island` (bind to the desktop shortcut of your choice) |
| New session | Ctrl+Shift+T / `newSession` |
| Close session | Ctrl+Shift+W / `closeTerminal` |
| Previous/next session | Ctrl+Shift+Left/Right / `prev` / `next` |
| Select session | Ctrl+Shift+1–9 / `goTo "1"` (one-based) |
| Run a script in a fresh session | `run "git status"` |
| Type into the current session | `write "text"` |
| Read session/backend diagnostics | `status` (JSON; no terminal contents) |
| Copy/paste | Ctrl+Shift+C / Ctrl+Shift+V |
| Primary selection | Select with the mouse; middle-click to paste |
| Scroll history | Shift+PageUp/PageDown; Shift+Home/End |
| Search | Ctrl+Shift+F; Escape closes search |
| Fold the last command's output | Ctrl+Shift+Z |
| Font zoom | Ctrl+Plus/Minus; Ctrl+0 resets |

Shell integration enables command boundaries, completion status, and job
notifications. For Zsh, source the bundled `integration.zsh` from `.zshrc`:

```zsh
[[ -n "$K4TERM_INTEGRACION" && -f "$K4TERM_INTEGRACION" ]] && source "$K4TERM_INTEGRACION"
```

It is idempotent and only emits marks inside a k4term session. The island
starts in the home directory. Shell configuration and preferences come from
`$SHELL` and `${XDG_CONFIG_HOME:-$HOME/.config}/k4term/k4term.conf`.
Automatic tmux startup should be skipped when `TERM_PROGRAM=k4term` so the
island owns independent sessions and receives command marks directly.

## Backend protocol

The session speaks the existing k4term JSON-line protocol. Compatibility
keys retain their names. The bundled backend adds optional `width` (terminal
cells) to text runs, `cursor_visible` to frames, and a `ready` message at a
shell prompt. Older native frames remain supported. Without prompt marks,
the view waits for a quiet initial frame before sending a queued command.

Text, classic keyboard sequences, alternate screens, scroll regions,
256/truecolor, bracketed paste, SGR/legacy mouse input, and common OSC
sequences are supported. Graphic protocols such as sixel and Kitty images,
progressive keyboard reporting, and line reflow on resize are not supported.
Unsupported control strings are consumed without hiding later output.

## Verification

```sh
python3 -B plugins/Terminal/island.py --selftest
python3 -B tools/test_terminal.py
nix build .#checks.x86_64-linux.terminal
```

The regression suite covers screen content, control sequences, Unicode cell
coordinates, command boundaries, backpressure, an isolated Bash/Zsh startup,
PTY resize, a 256 KiB input transfer, and child-process cleanup.
