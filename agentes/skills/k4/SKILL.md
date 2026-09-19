---
name: k4
description: >
  Use this whenever the user is on a machine running k4 — the Dynamic
  Island-style bar for Hyprland — and wants to change what the bar does, write
  a plugin for it, or debug one. Triggers: k4, the island, the bar, a k4
  plugin, plugin.json, K4.Plugin, quickshell ipc call k4, pluginReload,
  pluginStatus, ~/.config/k4/plugins, the k4 launcher, the k4 control center,
  k4 shortcuts. Also use it when the
  user says "make me a widget/plugin for my bar" and the bar is k4.
---

# k4

[k4](https://github.com/k4ditano/k4) is an extensible bar for Hyprland, built
on Quickshell. It sits collapsed at one edge of the screen and expands when it
has something to show.

**Native host features and installable plugins have different roles.** The
pill, volume HUD, sound mixer, clock, player, notifications, control center,
session and tray are native host features. The launcher, settings and other
installable modules are plugins. External plugins use the public `K4` API,
just as repository plugins should; native host internals are not templates to
copy into a plugin. Read the API reference before assuming a native feature
is available to an external plugin.

## Where things are

```
~/.config/quickshell/k4/          the bar itself (the repository)
~/.config/k4/plugins/<id>/        plugins the user installed or wrote
~/.local/state/k4/plugins.json    which plugins are on
~/.local/state/k4/k4.log          the log — read this first when something breaks
```

## Read the right guide

- [`plugins.md`](plugins.md) — writing a plugin: the fastest path, the API, permissions, testing it without touching the running bar, publishing it.
- [`barra.md`](barra.md) — driving and debugging the bar itself: IPC, the log, restarting, shortcuts, and language policy.

## Language and compatibility

Write new prose, comments, UI strings and identifiers in English. The UI uses
plain English literals, with no translation layer. Existing Spanish API names,
paths and contract values stay until their coordinated migration; do not invent
English replacements that the current host does not implement. Use English
manifest keys while preserving the actual permission and surface values listed
in `docs/PLUGINS.md`. Local `AGENTS.md` instructions take precedence over this
skill, including migration sequencing and operational guidance.

## Three things to get right from the start

**Read the log before guessing.** `~/.local/state/k4/k4.log` has the QML
errors, and `quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4
pluginStatus` tells you which plugins failed and why. A plugin that does not
appear almost always has an error waiting there.

**Never restart the bar to test a plugin.** `python3 tools/plugins.py --test
<id>` opens it in a separate instance with no bar, no services and no
notifications. If it hangs, it hangs alone. Restarting the user's bar loses
whatever they had open.

**Declare what you use.** A plugin lists its permissions in `plugin.json`, and
`tools/plugins.py` checks that list against what the QML actually calls. Using
something you did not declare does not warn — it makes the plugin refuse to
load. That is deliberate, and it is also the fastest way to find out you
forgot one.
