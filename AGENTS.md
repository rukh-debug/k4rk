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
