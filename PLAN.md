# Neat & Conventional k4 — Refactor Program

Audit-driven program to make the plugin ecosystem fully framework-conformal:
no cross-plugin reach-ins, no duck-typed host calls, no Arch-only code in the
Launcher, no undeclared tool dependencies, and the settings ownership rule
written down.

**Decisions locked with the owner (2026-08-31):**

- Settings model: **codify the central registry** — `services/Settings.qml`
  stays the host registry for cross-cutting knobs; plugin-private knobs go
  through `K4.Ajustes`. No page-contribution API will be built.
- Upstream: this fork has **diverged for good** from k4ditano/k4 — optimize
  for this repo's cleanliness, no merge constraints.
- Launcher packages: **extract into its own plugin**. Package management is
  not the Launcher's job; it leaves through the sanctioned door
  (`K4.Lanzador` contributed results). No new backends (no nix backend).
- Tool gating: **extend `requiere` to binaries** (`"requiere": "bin:codex"`).

Commit discipline: each phase is verified (build + restart + `pluginStatus`
+ phase checks) and committed separately, only after the owner confirms.

---

## Phase 0 — Defects & hygiene

1. **Sparse array bug** — `services/Settings.qml` `definicion: [,,` has two
   holes → `TypeError: Cannot read property 'grupo' of undefined` at
   AjustesView.qml:136 on every Settings search. Drop the holes.
2. **Wallpaper dir dedupe** — `plugins/HyprTheme/HyprThemePlugin.qml`
   duplicates `services/Fondos.qml`'s `/usr/share/wallpapers`,
   `/usr/share/backgrounds` list. HyprTheme consumes Fondos' single list.
3. **Name the pill id** — constant (`Island.pillId`); replace the magic
   `"idle"` strings in `shell.qml` (9 sites) and any in services.
4. **K4.Sonido XDG path** — `/usr/share/sounds/freedesktop/stereo/` becomes
   a named constant with a comment (no behavior change).

Verify: `nix build .#k4`, restart, `pluginStatus` 22/0, Settings search
produces no TypeError in `~/.local/state/k4/k4.log`.

## Phase 1 — Reference formalization

1. **Generic reference injection** — drop the `referencias` map
   (services/PluginManager.qml): any plugin declaring `property var <x>`
   where `<x>` matches a catalog id receives the live instance (null when
   off/broken). Startup warning when a declared property looks like an id
   but matches none (typo guard).
2. **Convert reach-ins:**
   - `LauncherPlugin` declares `property var apps` → replaces
     LauncherView.qml:505 `PluginManager.instancia("apps")`.
   - `SettingsPlugin` declares `property var theme` → replaces the 7
     `PluginManager.instancia("hyprtheme")` sites (AjustesView.qml:839-1007,
     PortadaFamilia.qml:40); views read via `vista.plugin.theme`.
   - `shell.qml`'s `_p()` compat layer stays — reaching by id is its job.

Verify: build/restart/IPC; toggle HyprTheme off → colour pages show their
engine-off state; launcher still lists plugin apps.

## Phase 2 — Settings pages & placement (DONE, direction-adjusted)

Added mid-program by owner request. Sub-parts, as landed:

- **2.0** Null-guarded every `motor.*` read in the Display-family
  widgets; the engine-off notice moved above the wallpaper grid; the
  Display hero says "The theme plugin is off" instead of a misleading
  "No wallpaper set"; FilaOpcion undefined-warnings fixed.
- **2.1 `K4.Pagina`** — plugins contribute whole Settings pages:
  registered in `Enganches.paginas`, appended to
  `Settings.definicion`, rendered by one generic Loader that asks the
  registry for the Component by (plugin, name) — never through
  modelData copies. Swept with the plugin: off author, no page.
- **2.4 migration** — Colour/Windows/Effects moved out of AjustesView
  into HyPrTheme as `K4.Pagina { padre: "Display" }` contributions
  (widgets physically in `plugins/HyprTheme/`); Wallpaper and Fonts
  stay host-owned. The null-motor bug class died by construction.
- **2.2 informational (toggles reverted)** — per-page enable/disable
  was built (`services/Paginas.qml`) and reverted by owner decision:
  the plugin's own switch is the decision; FilaPlugin tells what it
  buys in a "What it adds" group (pages + destination, launcher
  results). While here: toggling a plugin no longer resets Settings to
  its first page (the island's content is one Loader keyed on the
  visible view, not a Repeater over the churning instance list), and
  plugin rows keep their open state across roster rebuilds
  (`AjustesView.filasAbiertas`).
- **2.3 placement derived** — `K4.Plugin.colocable` contract property;
  `PlacementPage.vistas` derives from live instances instead of a
  hardcoded 16-entry list. HyPrTheme dropped from the cards (it no
  longer has a surface); disabled plugins show no card.
- **2.5 docs** — `docs/API.md` + `api/LEEME.md`: K4.Pagina,
  `colocable`, the `"paginas"` permission for external contributors
  (tools/plugins.py PERMISOS). *Pending.*

## Phase 3 — Contract formalization

1. **One verb, one method** — replace multi-poke sequences in shell.qml's
   compat layer with single methods plugins own:
   - `k4 search`: `launcher.buscar(q)` instead of open/query/rebuild pokes.
   - `k4 askNow/askFollowUp/askScreen/askRegion`: `ask.preguntar(texto)`,
     `ask.preguntarConImagen(tipo)` instead of openAsk/query/send pokes.
2. **Declare optional verbs** in `K4.Plugin` as documented no-op stubs:
   `toggle(tab)`, `openTab(tab)`, `abrirPagina(page)`, `buscar(q)`,
   `preguntar(texto)` — contract visible, host calls unconditional.
3. Document in `docs/API.md`.

Verify: IPC round-trip of every touched verb (`k4 askNow hi`, `k4 search
foo`, `k4 settingsSection wallpaper`, `togglePanel`, `toggleNotifications`,
`wifi`, `bluetooth`, `sound`, `theme`).

## Phase 4 — Packages extraction (the big one)

New `plugins/Packages/` — id `packages`, `aplicacion: true`, permisos
`["procesos"]`, self-gating by binary probe.

1. **Moves in:**
   - Search: `pacman -Ss` / `yay -Ss --aur` + parsing (LauncherPlugin.qml
     ~31-260).
   - Installed list (`pacman -Qq`), install (`sudo pacman -S`) and
     uninstall (`sudo pacman -Rns`) flows.
   - Updates counting: absorb `services/Paquetes.qml` (checkupdates /
     `yay -Qua`, 10-min cache) — the service is deleted.
2. **Sanctioned integration:**
   - Package rows reach the launcher via `K4.Lanzador` (below apps, by
     design). Extend the row schema minimally if needed (`insignia` badge
     text: repo/aur/installed) — rendered generically by Launcher, no
     package-specific code there.
   - `elegir` → the plugin's own confirm/progress view in its own island.
   - Apps' updates badge: `property var paquetes` reference (phase 1).
   - `k4 install <q>` verb → `_p("packages")?.buscar(q)`;
     `openPackageSearch` deleted.
3. **Launcher slimmed:** packages mode, both row templates, all
   processes/state out (~450 lines); the `mode` concept deleted.
4. **On NixOS:** binary probe at start; no pacman/yay → zero contributed
   results, no updates badge, no failed-process warnings in the log.

Verify: clean log on this machine, launcher search intact, plugin row in
Settings, IPC verbs work. Full install/remove flows need an Arch box — out
of test reach here; note in commit.

## Phase 5 — Binary requirements (DONE)

`services/Binarios.qml` probes every `bin:` the catalog names in one
batched `command -v` sweep, re-probes every 30 s while something is
missing, and notifies on change. `PluginManager.requisitoCumplido`
understands `"requiere": "bin:<name>"` with an honest "needs 'x'
installed" reason; `_sincronizar` gates CREATION on requirements too
(an unmet plugin can no longer resurrect via catalog rescans); Ask
declares `"require": "bin:codex"`. Verified live in both directions
with a scratch requirement: destroy, stay-dead across rescans, revive
on removal.

## Phase 6 — Codification in docs (DONE)

The ownership rule written at the top of `services/Settings.qml`;
reference-by-id and `bin:` requirements in `docs/API.md`; AGENTS.md
carries the architecture rules and the ops notes (flake staging, the
runtime-registry clearing). `api/LEEME.md` covers `K4.Pagina`.

**Execution order:** 0 → 1 → 2 → 3 → 4 → 5 → 6 — all done.

---

**Execution order:** 0 → 1 → 2 (done) → 3 → 4 (depends on 1+3) → 5 → 6.

**Out of scope, flagged:** TerminalIslaView.qml:765's 16 ms timer (looks
like a game-loop; unverified), any nix package backend.
