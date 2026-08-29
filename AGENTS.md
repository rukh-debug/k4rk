# Language: English only

All agent-written text — comments, commit messages, docs, issues, replies —
is in English. Never write Spanish (or any other language). Translate any
Spanish comments in files you touch. UI strings are plain English literals;
there is no translation layer anymore.

IPC verb/target names (`captura`, `retomar`, `isla`, `mudar`, …) and the
Spanish service/property/function names that already exist (`abrir()`,
`posicionBarra`, …) are API identifiers — leave them as designed and extend
the existing pair instead of adding a second name.

Full k4 context (build, IPC surface, bind ownership, tooling):
`~/.agents/skills/k4/SKILL.md`
