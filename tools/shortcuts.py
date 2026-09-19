#!/usr/bin/env python3
"""Read keyboard shortcuts configured in Hyprland.

Read the configuration rather than `hyprctl binds`: with Lua configuration,
hyprctl reports `dispatcher: __lua` and `arg: 6`, identifying keys but not their
actions. Its JSON also has mismatched keys and values in the tested version.
The file describes each action and groups bindings using section comments.

    shortcuts.py

Emit {total, shortcuts}, with combo, description, detail and section per entry.
"""

import json
import os
import re
import sys

CONFIG = os.path.expanduser("~/.config/hypr/config")
# Home Manager writes user bindings and `require("config.k4")` in the main
# Lua configuration. Reading only the config directory missed all user binds.
# Put the main file first so user bindings are easy to find.
MAIN_CONFIG = os.path.expanduser("~/.config/hypr/hyprland.lua")


def config_files():
    """Return the main hyprland.lua and config/ Lua files that bind keys.

    User bindings live in `~/.config/hypr/hyprland.lua`, written by HM; k4's
    installer puts its own in `config/k4.lua` to avoid editing the user file.
    Read every .lua containing `hl.bind` in a stable order across launches.
    """
    paths = []
    if os.path.isfile(MAIN_CONFIG):
        try:
            with open(MAIN_CONFIG) as source:
                if "hl.bind" in source.read():
                    paths.append(MAIN_CONFIG)
        except OSError:
            pass
    try:
        names = sorted(os.listdir(CONFIG))
    except OSError:
        return paths
    for name in names:
        if not name.endswith(".lua"):
            continue
        path = os.path.join(CONFIG, name)
        try:
            with open(path) as source:
                if "hl.bind" not in source.read():
                    continue
        except OSError:
            continue
        paths.append(path)
    # Main file first, then `binds.lua` with its recognizable user sections.
    paths.sort(key=lambda path: (path != MAIN_CONFIG, os.path.basename(path) != "binds.lua", path))
    return paths

# Anchor at the end: without `$`, `local k4 = "a" .. root .. "b"` matched only
# the first fragment and produced an incomplete command.
RE_LOCAL = re.compile(r'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"\s*(?:--.*)?$')
RE_GLOBAL = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*=\s*"([^"]*)"\s*(?:--.*)?$')
RE_NUM = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(\d+)')
RE_BIND = re.compile(r'hl\.bind\s*\(\s*(.+)$')
RE_FOR = re.compile(r'^\s*for\s+(\w+)\s*=\s*(\w+)\s*,\s*(\w+)\s*do')
# Loops often use `local key = i % 10` and bind `key`. Track that alias so the
# displayed combination does not contain the literal "+ key".
RE_ALIAS = re.compile(r'^\s*local\s+(\w+)\s*=\s*.*\b%s\b')
# `local k4 = "quickshell ipc -p " .. root .. "/shell.qml call k4 "`
RE_LOCAL_EXPR = re.compile(r'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$')

# What each dispatcher does. The phrase carries «%1» where the detail goes;
# the view fills it in. Unknown dispatchers come out with their clean name,
# which still says plenty.
DISPATCHER_LABELS = {
    "window.close": "Close the window",
    "window.fullscreen": "Fullscreen",
    "window.float": "Float or tile the window",
    "window.move": "Move the window",
    "window.resize": "Resize",
    "window.cycle_next": "Next window",
    "window.pin": "Pin the window",
    "window.pseudo": "Pseudo mode",
    "focus": "Change focus",
    "workspace": "Go to workspace",
    "layout": "Change layout",
    "global": "Bar global event",
    "exit": "Exit Hyprland",
    "kill": "Kill a window",
    "exec_cmd": "",              # resolved from the command itself
}


def read_variables():
    """Collect variable values needed to reconstruct strings."""
    values = {}
    paths = [os.path.join(CONFIG, "variables.lua")] + config_files()
    for path in paths:
        try:
            with open(path) as source:
                text = source.read()
        except OSError:
            continue
        for line in text.split("\n"):
            for rx in (RE_LOCAL, RE_GLOBAL):
                m = rx.match(line)
                if m:
                    values[m.group(1)] = m.group(2)
                    break
            else:
                m = RE_NUM.match(line)
                if m:
                    values[m.group(1)] = m.group(2)
                    continue
                # k4.lua builds its three IPC prefixes by concatenating the
                # root path. Resolve those too so command labels stay readable.
                m = RE_LOCAL_EXPR.match(line)
                if m:
                    value = resolve_literal(m.group(2), values)
                    if value is not None:
                        values[m.group(1)] = value
    return values


def resolve_literal(expr, values):
    """Resolve a Lua expression to a string, or None if any part is unknown."""
    fragments = []
    for part in expr.split(".."):
        part = part.strip()
        if not part:
            return None
        if part.startswith('"') and part.endswith('"') and len(part) >= 2:
            fragments.append(part[1:-1])
        elif part in values:
            fragments.append(values[part])
        else:
            return None
    return "".join(fragments) if fragments else None


def resolve_expression(expr, values, loop_aliases=None):
    """Join a Lua concatenation expression into a string."""
    fragments = []
    for part in expr.split(".."):
        part = part.strip()
        if not part:
            continue
        if part.startswith('"') and part.endswith('"'):
            fragments.append(part[1:-1])
        elif part in values:
            fragments.append(values[part])
        elif loop_aliases is not None and part in loop_aliases:
            fragments.append("№")          # loop marker, replaced later
        else:
            fragments.append(part)
    return "".join(fragments)


def split_arguments(text):
    """Split hl.bind arguments while respecting parentheses and quotes."""
    depth = 0
    quoted = False
    for i, c in enumerate(text):
        if c == '"' and (i == 0 or text[i - 1] != "\\"):
            quoted = not quoted
        elif not quoted:
            if c in "({[":
                depth += 1
            elif c in ")}]":
                depth -= 1
            elif c == "," and depth == 0:
                return text[:i], text[i + 1:]
    return text, ""


def until_closing_parenthesis(text):
    """Return the contents up to the closing parenthesis.

    `rstrip(")")` fails when another argument follows: in
    `hl.dsp.exec_cmd(k4 .. "togglePlay"), { locked = true })`, it included
    `{ locked = true }` in the command.
    """
    depth = 0
    quoted = False
    for i, c in enumerate(text):
        if c == '"' and (i == 0 or text[i - 1] != "\\"):
            quoted = not quoted
        elif not quoted:
            if c in "({[":
                depth += 1
            elif c in ")}]":
                if depth == 0:
                    return text[:i]
                depth -= 1
    return text


def describe_action(action, values):
    """Return (description, detail), with «%1» marking where the detail goes.

    The view fills %1 with `detail` — a command, a mode, a direction. The
    detail passes through as-is: that is exactly right for commands and mode
    names, which are literals.
    """
    action = action.strip().rstrip(")").strip()

    m = re.match(r'hl\.dsp\.([A-Za-z_.]+)\s*\((.*)$', action, re.S)
    if not m:
        # User functions such as `enter_submap("screenshot", …)` and
        # `run_and_reset("record start …")` have useful names and arguments
        # even though they are not dispatchers. Show a readable name and first
        # argument instead of raw Lua truncated mid-quote. For an anonymous
        # function, inspect its body.
        m5 = re.match(r'^function\(\)\s*(.+?)\s*end$', action, re.S)
        if m5:
            return describe_action(m5.group(1), values)
        m4 = re.match(r'^([A-Za-z_]\w*)\s*\(\s*"?([^",)]+)', action)
        if m4 and m4.group(1) != "hl":
            verb = m4.group(1).replace("_", " ")
            return verb + " · %1", m4.group(2).strip()
        # Also handle no-argument calls such as `reload_with_status` and
        # `set_cursor_zoom()`, whose closing parenthesis may have been stripped.
        m6 = re.match(r'^([A-Za-z_]\w*)\s*\(?\s*\)?\s*$', action)
        if m6:
            return m6.group(1).replace("_", " "), ""
        return action[:80], ""

    name, arguments = m.group(1), until_closing_parenthesis(m.group(2))

    if name == "exec_cmd":
        command = resolve_expression(arguments, values).strip()
        # Three common long command prefixes.
        if "quickshell ipc" in command:
            # Handle both `call k4 togglePanel` and `call k4.apps open`: modules
            # publish their own targets. Splitting only on "call k4 " left
            # module commands unshortened, including their full paths.
            m3 = re.search(r'call\s+k4(?:\.(\w+))?\s+(.*)$', command)
            if m3:
                module = (m3.group(1) + " ") if m3.group(1) else ""
                return "k4 · %1", module + m3.group(2).strip()
            return "k4 · %1", command.split("call k4 ")[-1].strip()
        if command.startswith("noctalia msg "):
            return "noctalia · %1", command[len("noctalia msg "):].strip()
        if command.startswith("uwsm app -- "):
            return "Open %1", command[len("uwsm app -- "):].strip()
        # Show arbitrary commands verbatim: translating them misrepresents
        # what will actually run.
        return command[:70], ""

    base = DISPATCHER_LABELS.get(name, name.replace(".", " · ").replace("_", " "))
    detail = ""
    for key in ("direction", "mode", "action", "workspace", "monitor", "window"):
        m2 = re.search(key + r'\s*=\s*"?([^",}]+)"?', arguments)
        if m2:
            detail = m2.group(1).strip()
            break
    if not detail:
        m2 = re.match(r'\s*"?([^",)]+)"?', arguments)
        if m2 and m2.group(1).strip():
            detail = m2.group(1).strip()

    # Loop variables add no useful detail: the combination already shows the
    # range. A truncated Lua table such as `{ x = delta[1]` is also unhelpful.
    if detail in ("i", "key"):
        detail = "the number"
    elif detail.startswith("m~"):
        detail = "on this monitor"
    elif detail.startswith("{"):
        detail = ""

    return (base + " · %1", detail) if detail else (base, "")


def read_shortcuts():
    values = read_variables()
    entries = []
    for path in config_files():
        try:
            with open(path) as source:
                lines = source.read().split("\n")
        except OSError:
            continue
        entries.extend(parse_config(lines, values))
    return entries


def parse_config(lines, values):
    entries = []
    section = "General"
    loop = None
    aliases = set()
    upper_bound = ""

    for line in lines:
        stripped = line.strip()

        # Section headings: ---- TITLE ----, -- Title, or -- ── Title ──────.
        # Editor-inserted box-drawing lines are not `-`; missing them placed
        # every binding in "General".
        m = re.match(r'^-{2,}\s*─+\s*(.+?)\s*─+\s*$', stripped)
        if m and m.group(1).strip("─- "):
            section = m.group(1).strip("─- ").capitalize()
            continue
        m = re.match(r'^-{2,}\s*(.+?)\s*-{2,}$', stripped)
        if m and m.group(1).strip("- "):
            section = m.group(1).strip("- ").capitalize()
            continue
        m = re.match(r'^--\s+([A-ZÁÉÍÓÚÑ][^.]{3,60})$', stripped)
        if m:
            section = m.group(1).strip()
            continue

        m = RE_FOR.match(line)
        if m:
            loop = m.group(1)
            aliases = {loop}
            upper_bound = values.get(m.group(3), m.group(3))
            continue
        if stripped == "end":
            loop = None
            aliases = set()
            continue

        if loop:
            m = re.compile(RE_ALIAS.pattern % re.escape(loop)).match(line)
            if m:
                aliases.add(m.group(1))
                continue

        m = RE_BIND.match(stripped)
        if not m:
            continue

        key, action = split_arguments(m.group(1))
        combo = resolve_expression(key, values, aliases if loop else None)
        if "№" in combo:
            combo = combo.replace("№", "1–" + str(upper_bound))

        description, detail = describe_action(action, values)
        entries.append({
            "combo": combo.strip(),
            "description": description,
            "detail": detail,
            "section": section,
        })

    return entries


def main():
    shortcuts = read_shortcuts()
    print(json.dumps({"total": len(shortcuts), "shortcuts": shortcuts}), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
