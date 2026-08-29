# Language: English only

All agent-written text — comments, commit messages, docs, issues, replies —
is in English. Never write Spanish (or any other language), even though this
codebase's README, UI strings, and IPC verbs are Spanish. Translate any
Spanish comments in files you touch.

Exceptions are runtime data, not prose — leave them as designed:

- String literals inside `Idioma.t("…")` / `Idioma.f("…")` are the i18n KEYS
  (Spanish by design; `traducciones/<code>.json` maps from them — rewriting a
  literal silently orphans its translations). New user-facing strings still go
  through `Idioma.t`.
- IPC verb/target names (`captura`, `retomar`, `isla`, `mudar`, …) are API
  identifiers.

Full k4 context (build, IPC surface, bind ownership, tooling):
`~/.agents/skills/k4/SKILL.md`
