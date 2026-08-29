# TODO

## Comments: Spanish to English, one directory at a time

The interface is English now; the comments still speak Spanish. Every
folder — core/, services/, widgets/, plugins/, tools/, the scripts —
carries prose comments in the old voice, and they are worth keeping:
most of them explain WHY, not what. This is a translation sweep, not a
rewrite.

- One directory (or plugin) per commit, so a review can read it. Start
  with `services/` — the most commented — then `core/`, `widgets/`,
  `plugins/` one at a time, `tools/` and the shell scripts last.
- Translate, never summarize. The long «why» blocks are the asset; a
  sentence stays a sentence, a list stays a list.
- Identifiers stay Spanish (`abrir()`, `posicionBarra`, the IPC verbs):
  they are API names, and renaming them is its own project, not part of
  this sweep.
- Runtime data stays as designed: keys, paths, output labels that tools
  read back. Only prose moves.
- After each directory, run the checks — `tools/plugins.py`,
  `tools/api.py`, `tools/guia.py` — and diff with `git diff --check`.
  Comments only, but cheap to prove nothing else moved.

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
