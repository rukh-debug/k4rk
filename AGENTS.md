# Language: English only

All agent-written text — comments, commit messages, docs, issues, replies —
is in English. Never write Spanish (or any other language). Translate any
Spanish comments in files you touch. UI strings are plain English literals;
there is no translation layer anymore.

The same goes for anything new you introduce: IPC verbs, plugin ids,
settings keys, permissions, stored values, subcommand names — English from
the start.

What still carries its original Spanish (being swept, see TODO.md): prose
comments everywhere, code identifiers (`abrir()`, `posicionBarra`), QML
file and folder names (`Sonido/`, `AccesosDirectos.qml`), and the
`K4.*` API type names. Do not rename them opportunistically inside
unrelated work — follow the TODO.md sweep so each batch is verifiable.

Exceptions that are NOT translation work:

- The terminal conf keys (`tamaño`, `opacidad`, …) are k4term's own config
  file format — an external binary's contract.
- Marker words the k4term shell integration emits (`donde`, session OSC
  payloads) come from the terminal, not from us.

Full k4 context (build, IPC surface, bind ownership, tooling):
`~/.agents/skills/k4/SKILL.md`

# Architecture rules (the short version)

- **Settings ownership**: cross-cutting knobs (two or more readers, or
  previewed by Settings' mock pages) live in `services/Settings.qml`.
  Single-reader knobs belong to their plugin via `K4.Ajustes`; whole
  pages belong to the plugin that does the work via `K4.Pagina`. The
  rule is written in full at the top of `services/Settings.qml`.
- **Plugins never import each other.** Reach another plugin by
  declaring `property var <catalog-id>` — the host injects the live
  instance (or null). `PluginManager._repartir` is the handout.
- **Host→plugin calls go through contract verbs** (`toggle`, `buscar`,
  `preguntar`, … — declared as stubs on `K4.Plugin`), never property
  pokes.
- **Only summoned surfaces get Placement cards**: `colocable: true` on
  the plugin. Wings, transients and indicators never.
- **Binary dependencies are declared, not tried**: `"require":
  "bin:codex"` in the manifest; `services/Binarios.qml` answers and
  revives.

# Ops notes (learned the hard way)

- New files must be `git add`-ed before `nix build .#k4` — flakes
  exclude untracked files.
- Restarting the bar for verification: kill by pid (`kill -9 $(pgrep -x
  quickshell)`), wait for death, and clear
  `/run/user/1000/quickshell/by-id` if IPC says "not ready" forever —
  SIGKILL cycles leave stale instance locks there.
