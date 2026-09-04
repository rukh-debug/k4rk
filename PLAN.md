# Plugin Audit: fixes, standardization, English sweep

Audit-driven program over every repo plugin (23 folders, ~21k lines): fix
the bugs the audit verified, standardize against the current contract
(dual-read manifest keys, honest `permisos`, contract verbs, `colocable`
correctness, registration ids), and translate the Spanish that remains —
UI strings and comments — per the TODO.md discipline (translate, never
summarize).

**Decisions locked with the owner (2026-09-02):**

- **Manifest vocabulary**: dual-read now — code accepts English
  `icon`/`application`/`permissions`/`require` alongside the Spanish
  keys; repo catalog, docs and examples write English. Wild Spanish
  manifests keep working; the TODO sweep finishes the rename later.
- **IPC names**: `k4.term`/`k4.theme` stay (muscle memory); the
  deviation is documented, `k4.<id>` remains the rule for new plugins.
- **Contract verbs**: the Ask trio (`openAsk`/`withScreenshot`/
  `withRegion`) and Packages' `actualizarTodo`/friends become
  documented `K4.Plugin` verbs — stubs + docs in the same change
  (the docs-must-follow law).
- **Scope**: bugs + standardization + English now; `K4.Card` adoption
  (Packages/Agentes/System) is its own future task.

Commit discipline: one plugin (or one coherent host slice) per commit,
each verified (checkers green → `nix build` → restart ritual →
`pluginStatus` 25/0 → log grep 0 → tray canary → phase smokes) before
the next.

---

## Phase 0 — Host contract

1. **Dual-read manifest keys** — `services/PluginManager.qml` and
   `tools/plugins.py` accept English `icon`/`application`/
   `permissions`/`require` alongside `icono`/`aplicacion`/`permisos`/
   `requiere`, English preferred. `plugins/catalog.json` rewritten to
   English keys. Docs teach English keys with a "Spanish aliases still
   accepted" note; `ejemplos/*` manifests updated. Fixes the doc lie
   where `"require"` silently no-ops today.
2. **Emergency catalog refresh** — `PluginManager.qml` fallback lists
   all 23 plugins, not 15.
3. **`validar_repo` hardening** — `tools/plugins.py` gains the
   user-plugin checks for repo plugins too: permissions declared for
   spawners, icon + description present. Catalog brought honest:
   `permissions: ["procesos"]` for the ~10 spawners, description +
   icon on all 23.
4. **`PluginManager.qml:592`** — `· pide:` → English (`· needs:`).
5. **IPC deviation note** — one line in `docs/API.md` marking
   `k4.term`/`k4.theme` as legacy names.

## Phase 1 — Bug fixes

**Commit A (stuck-state + races):**

- **Ssh** — `alternar()` and the IPC lambdas call the real `open()`
  (SshPlugin.qml:173, :900-902; today they hit the base
  `K4.Plugin.abrir()` → `toggle()` → a direct `active` write that
  breaks the `active: abierto || cerrando` binding and deploys a
  keyboard-less, viewless island). Add `close()` for the
  Escape/outside-click door. IPC `connect` re-runs its lookup after
  `fSsh.onLoaded` instead of searching stale data (:906-910).
- **Packages** — pending-query flag restarted from `onTerminado`
  instead of `parar(); running = true` (which drops the newest search,
  :177-203). Add `close()` (:308).
- **HyPrTheme** — notifiable `persistido` property; `GuardarTema.qml`
  binds to it instead of a method result that never re-evaluates
  (:21-23). `pendiente` flag in `apply()` re-fired in `onTerminado` so
  the last drag step lands (HyPrThemePlugin.qml:332-336).
- **Terminal** — same pending-flag fix for the pill-click
  `hyprctl clients` restart (:824-826). Add `close()` (:236). Guard
  the `estela` config field (SesionIsla.qml:106).

**Commit B (Settings + Agentes):**

- **Settings** — `bloque()` null-guard at the five PanelEditor call
  sites (kills the transient registration-race TypeError,
  PanelEditor.qml:236-374). Placement dot updates the in-memory map
  live and saves on release only (PlacementPage.qml:283-289). Delete
  the dead `dual`-plugin branch (PrevioIsland.qml:81-85).
- **Agentes** — skip pill re-register when `(pct, color)` unchanged
  (:206-207). Island height `28`→`30` per limit row (:73-83).

## Phase 2 — Standardization

1. **Registration-id migrations** (the orphan-bug class; one-shot
   value migrations per the TODO pattern — read old, write new):
   - Agentes: `K4.Guardado`/`K4.Ajustes`/`K4.Lanzador`/pill id
     `agentes` → `agents`; option ids `enVivo/avisar/umbral` →
     English with value migration; `agentes.limite` → `agents.limit`.
   - Pantallas: `K4.Guardado plugin:` `pantallas` → `displays` with
     state-file migration.
   - Player: `asomarAlCambiar` → `peekOnChange` with value migration.
   - HyPrTheme: state-file keys `fondos/transicion/paletaAuto` →
     English, one-shot rewrite of `~/.local/state/k4/hyprtheme.json`.
2. **Contract verbs + docs** — `K4.Plugin` gains stubs for the Ask
   family (`openWith`/`withScreenshot`/`withRegion`) and Packages
   (`updateAll`/`refresh`); `shell.qml`, `AppsPlugin.qml`,
   `LauncherView.qml` route through them; `docs/API.md` +
   `docs/PLUGINS.md` verb lists updated in the same change.
3. **colocable** — remove from Toast (transient, never a Placement
   card); add to Sonido (summoned view, gets a Placement card).
4. **Titles/versions** — catalog↔QML title alignment
   (Notifications/Displays/Applications/Control centre); version
   bumps for every plugin meaningfully touched.

## Phase 3 — English sweep (one plugin per commit)

- **UI strings first** (one commit, user-visible):
  `pantallas.py` messages + its generated lua headers (marker regex
  renamed in tandem, writer+reader together); Ask chips
  `nueva/copiar/ampliar/guardar/abrir` → `new/copy/zoom/save/open`;
  HyPrTheme `aplicado` → `applied` + the Spanish line written into
  the user's `hyprland.lua` (text is free — `isPersisted()` matches
  a different marker); `registro.json` `_meta` keys → English with
  `tools/plugins.py` dual-reading during transition; qmldid template
  header in `tools/plugins.py`.
- **Comments, biggest-first**: Terminal (689) → HyPrTheme (454) → Ssh
  (210) → Settings leftovers (162: PrevioIsland/FilaOpcion/Version) →
  Agentes (102) → Panel (94) → Session (89) → Idle (74) → Apps (72)
  → Ask (64) → Launcher (45) → Toast (40) → Clock (28) →
  System/Player/Tray/Sonido/Clipboard/Keys (<25 each).
  Packages/Volume/Submap are already clean.

**Out of scope (external contracts, untouched)**: k4term conf keys,
`claves.json` fields, OSC markers, `--heredar`, bilingual launcher
keywords, `EN_ESPANOL` flag aliases. Spanish identifiers and file
names stay for the TODO.md identifier phase.

---

## Verification protocol (every commit — followed throughout)

1. `python3 tools/api.py && python3 tools/guia.py && python3
   tools/plugins.py` — all green.
2. `nix build .#k4 -o /tmp/opencode/k4-test --print-out-paths`.
3. Restart ritual: kill quickshell by pid, wait for death, clear
   `/run/user/1000/quickshell/{by-id,by-pid,by-path}`,
   `setsid nohup /tmp/opencode/k4-test/bin/k4 --no-duplicate`.
4. `pluginStatus` → 25 plugins / 0 errors; log grep
   (TypeError|Cannot read|is not defined) → 0; tray canary.
5. Phase smokes: `k4.ssh open` + outside-click closes; fast-typing
   package search never stalls; theme slider's last drag step lands;
   Placement drag = one disk write; Terminal pill click after motion;
   disable/reload agents+displays leaves no orphan rows; migrated
   settings survive a restart with old state files present.
