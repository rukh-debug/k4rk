# TODO

## Spanish leftovers: comments, then identifiers

The product surface is English now — UI strings, IPC verbs (`open`,
`move`, `goTo`…), plugin ids (`sound`, `displays`, `agents`), settings
keys (`barPosition`, `islandSpace`…), permissions, stored values and
subcommands, with one-shot migrations for the old names. Two layers
remain, and they go in this order:

### 1. Comments — translate, one directory at a time

Every folder — core/, services/, widgets/, plugins/, tools/, the scripts —
carries prose comments in the old voice, and they are worth keeping:
most of them explain WHY, not what. This is a translation sweep, not a
rewrite.

- One directory (or plugin) per commit, so a review can read it. Start
  with `services/` — the most commented — then `core/`, `widgets/`,
  `plugins/` one at a time, `tools/` and the shell scripts last.
- Translate, never summarize. The long «why» blocks are the asset; a
  sentence stays a sentence, a list stays a list.
- After each directory, run the checks — `tools/plugins.py`,
  `tools/api.py`, `tools/guia.py` — and diff with `git diff --check`.
  Comments only, but cheap to prove nothing else moved.

### 2. Identifiers — rename, only after the comments pass

`abrir()`, `posicionBarra`, `carpetasFuera`… plus the QML file names
(`AccesosDirectos.qml`) and folder names (`Sonido/`), and last the
`K4.*` API type names (`K4.Isla`, `K4.Sonido`), because those are the
public API and renaming them breaks every outside plugin at once.

- Same discipline: one directory per commit, whole-word renames
  (`\bposicionBarra\b`), never by hand across files.
- The IPC verbs, settings keys, plugin ids and permissions are already
  English — done with migrations, not to be redone.
- Leave alone: k4term's conf keys (`tamaño`) and shell-integration
  markers (`donde`) — external contract, see AGENTS.md.

## User-created islands: a host system, not a plugin API

NOT implemented — this is the intent, nothing more.

Plugins must NOT be able to create new islands (an `api/K4/Isle`
experiment was built and removed on purpose: an island is real estate,
and real estate is the user's call, not a plugin's). What is wanted is
the opposite door: **by default, with no plugin involved, the user can
add new islands** — and every new island shares the WHOLE feature set
of the default one.

The shape of the thing:

- An island is created, placed, and removed by the user, from Settings
  or the island's own grip — the same ownership model as bar edge and
  alignment: persistent, user-owned, no code involved to get one.
- Each new island is a **full instance of the island machinery**, not a
  stripped sibling: silhouette, edge fusion, gliding, hover behavior,
  retirement, Placement, input mask, focus — everything the default
  island already does, instanced.
- The "different instance" part is the point: each island carries its
  own selection of what to show — its own modules/plugins assigned per
  island — so a user can install everything they like and then decide
  WHICH island each thing lives on. The default arbitration (one
  activePlugin, priority ladder) likely becomes per-island: each island
  arbitrates its own roster.
- Implied groundwork before any of this lands: the island window
  machinery living in `shell.qml` (one logical island, one arbitration,
  ~1400 intertwined lines: mask, focus, retirement, multi-screen
  variants) must be factored into a reusable host-side component —
  behavior-preserving, verified across hover views, summoned views,
  hidden-bar retirement, and every monitor.

## Agentes: per-provider toggles + more providers

NOT implemented yet — this is the plan, nothing more.

Today `plugins/Agentes` runs `tools/agentes.py` and shows two fixed
agents: Claude Code and Codex (their 5-hour and weekly windows, plus
Claude's separate Fable quota). The view, the pill alarm and the launcher
keywords are already agent-agnostic — the plugin layer is what isn't.

### 1. Enable/disable per provider

A new *Agentes* group in Settings: one toggle per provider (claude,
codex, and every one added below). `agentes.py --proveedores claude,zai`
(or the equivalent flag) so a provider that is off costs nothing — no
process, no read, no pill row. Default: claude and codex on, the rest
opt-in. Keys go into the Settings persistence list like every other
toggle.

### 2. New providers

- **z.ai — GLM Coding Plan.** HTTP, Bearer auth.
  - Key: `$ZAI_API_KEY` (China: `$ZHIPUAI_API_KEY`, and base swaps to
    `open.bigmodel.cn` — keys are NOT interchangeable between regions).
  - 5h rolling window: `GET https://api.z.ai/api/monitor/usage/quota/limit`
    → percentage + subscription plan. (Rolling, not wall-clock aligned —
    the countdown is an estimate, show it as such.)
  - Extras if cheap to add: `…/api/monitor/usage/model-usage`,
    `…/tool-usage`, `…/api/paas/v4/user/credit_grants` (grants expire in
    ≤30 days; monthly usage and credits).
- **OpenCode Go.** HTTP, one call:
  `GET https://opencode.ai/zen/go/v1/usage` → session (rolling 5h),
  weekly and monthly percentages with resets — the same numbers as the
  OpenCode dashboard. Key discovery: `OPENCODE_API_KEY` / `ZEN_API_KEY`
  env or OpenCode's `auth.json` (both the `opencode`/Zen and
  `opencode-go` catalog entries share one tile).

### 3. Architecture: steal the provider model, not the code

Get inspiration from how OpenUsage (openusage.sh, robinebers/openusage —
35 providers) and AIUsageTracker (rygel/AIUsageTracker) integrate
OpenCode and friends, so we can cover most providers with one shape:

- A provider = **detection** (env var / CLI auth file — no config unless
  detection is impossible) + **sources** (HTTP quota API as primary;
  local CLI logs only for what the API can't tell).
- Everything else is already per-agent in the view: one card per agent,
  one row per window (`limites[]`), pill shows the tightest one.
- `agentes.py` grows a provider registry: id, título, detectar(),
  consultar() → same `limites[]` JSON it emits today, so the QML does
  not learn a single new thing.
- Offline/`--sin-red` mode must keep working for file-based providers;
  HTTP providers just report "sin datos" when offline.

References studied: OpenUsage provider docs (opencode, zai pages),
opencode.ai/docs/go, opencode-go-usage tooling, AIUsageTracker PR #525.

### 4. change all filenames that is in spanish to english and every different occurance of that file, import export docs everything. - do proper research first, so we dont break stuff.
