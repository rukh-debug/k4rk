# Agents

Open **Settings → Agent providers** to search the full
[models.dev](https://models.dev) catalog, inspect provider information, and
enable supported usage integrations. The Agents usage surface also has a
**Manage providers** action. Its IPC target remains `k4.agents` with `toggle`,
`close`, and `refresh` verbs.

Every catalog entry is searchable, including unsupported providers. The
**All providers**, **Supported**, and **Enabled** filters apply before
pagination. Unsupported entries retain their details and documentation;
their usage switch is disabled.

## Usage integrations

| Catalog entry | Usage adapter | Default | Credential/data discovery |
| --- | --- | --- | --- |
| `anthropic` | `claude` — Claude Code subscription quotas | On | Claude Code login, OAuth credential file and local usage cache; honors `CLAUDE_CONFIG_DIR` |
| `openai` | `codex` — OpenAI Codex subscription quotas | On | Codex app-server account API with recent local rollout logs as the offline fallback; honors `CODEX_HOME` |
| `zai-coding-plan` | Global Z.AI Coding Plan | Off | `ZAI_API_KEY`, then the unambiguous `ZHIPU_API_KEY` alias |
| `zhipuai-coding-plan` | China Zhipu AI Coding Plan | Off | `ZHIPUAI_API_KEY`, then the unambiguous `ZHIPU_API_KEY` alias |
| `opencode-go` | OpenCode Go subscription | Off | `OPENCODE_API_KEY`, `ZEN_API_KEY`, then API-key entries in OpenCode's `auth.json` |

Claude Code and Codex CLI installation is detected. An enabled provider
without credentials or data shows setup/status information rather than a
fabricated zero. Claude credentials are never refreshed or rotated here.

Codex live checks use the installed CLI's versioned `account/read` and
`account/rateLimits/read` app-server methods. The CLI owns authentication; k4
does not read, copy, store, or send its ChatGPT token. With live checks off, the
adapter reads the newest recorded quota snapshot from Codex rollout logs.

The catalog's general API credentials are distinct from the credentials a
usage adapter needs. For example, `ANTHROPIC_API_KEY` is not a Claude Code
subscription login, and `OPENAI_API_KEY` does not replace Codex rollout data.
Each provider's details explain both kinds of setup. Copy buttons copy
environment-variable **names**, never secret values.

### Z.AI regions

The global and China Coding Plans have independent switches and keys. Each
key is sent only to its matching regional quota endpoint:

- Global: `https://api.z.ai/api/monitor/usage/quota/limit`
- China: `https://open.bigmodel.cn/api/monitor/usage/quota/limit`

models.dev publishes `ZHIPU_API_KEY` for both. That alias is accepted only
when exactly one region is enabled. To enable both, use the region-specific
`ZAI_API_KEY` and `ZHIPUAI_API_KEY` variables. Make them available to the bar's
launch environment and restart the bar; exporting a key in an unrelated
terminal does not update the running bar's environment.

The main token quota is a rolling window. If the API supplies a reset time,
the countdown is marked `≈`; if it does not, the view says **Rolling window**.
It never invents a wall-clock reset. Monthly tool quota from the same response
is displayed when available.

### OpenCode Go

The helper reads `$XDG_DATA_HOME/opencode/auth.json`, falling back to
`~/.local/share/opencode/auth.json`. Within that file, a nonempty API key under
`opencode-go` wins over `opencode`. Environment keys take precedence over
the file. OAuth entries are not treated as API keys.

`GET https://opencode.ai/zen/go/v1/usage` supplies rolling, weekly, and monthly
percentages and ISO reset timestamps. Both saved auth entries feed **one Go
card**. The catalog keeps the OpenCode Zen entry visible with a pointer to Go;
Zen credit tracking is not advertised as supported.

## Polling, persistence and offline behavior

- Provider choices, warning preferences and live mode belong to the plugin's
  `K4.Guardado` state under `~/.local/state/k4/plugins/agents/estado.json`.
  Existing warning/live settings are preserved. Current state takes precedence
  over the one-shot legacy-state migration.
- Settings load before any usage query. Disabled adapters perform no detection,
  credential reads, local-log scanning, or HTTP requests.
- Usage refreshes every 20 seconds while the usage surface or provider page is
  open, and every five minutes in the background when quota warnings or a
  pinned folded-pill quota are on.
- Turning a provider off removes its card and warning immediately. In-flight
  work is cancelled, obsolete responses are discarded, and the latest selection
  is queried after the previous process exits.
- All providers off means no usage process or usage polling. Browsing the
  catalog remains available independently.
- With **Live checks** off, Claude's CLI cache and Codex's local logs still
  work. HTTP-only providers report offline. Catalog refresh and logo requests
  are disabled.
- HTTP usage is cached for one minute, with a longer retry delay for rejected
  credentials or rate limiting. New-provider caches are partitioned by account
  fingerprint and endpoint; no credential is stored in the cache or output.

## Folded pill quota

The expanded Agents island always shows every enabled provider and all of its
available quota windows. The percentage shown on the main folded pill is
configured separately under **Quota on folded pill**:

- **Automatic warning** keeps the previous behavior: show the tightest quota
  only after it crosses the warning threshold.
- Every discovered provider/window pair is selectable independently, such as
  Claude Code **5 hours**, OpenAI Codex **Weekly**, or OpenCode Go **Monthly**.
  Selecting one pins that exact percentage on the folded pill even below the
  warning threshold.

Clicking a quota row in the expanded Agents view pins it directly; the selected
row is marked, and clicking it again returns to automatic warnings. The same
choice remains available in the plugin's **Quota on folded pill** setting.

Unavailable pinned data remains selected and resumes when that provider reports
the window again. Disabling the pinned provider returns to automatic warnings.
The stable `provider:window` choice is stored as `pinnedQuota` beside provider,
warning and live-check preferences.

## Control Centre

Agents contributes an **Agent usage** card to the Control Centre. Its compact
row shows the tightest enabled quota and opens the full usage view inside the
centre, where the standard Back button and Escape return to the card list. The
Control Centre editor owns card visibility, ordering and its enable/disable eye
like every other contributed card. Opening either the card or its detail page
keeps usage polling active; hiding it stops that foreground polling.

## Catalog and logos

The bundled snapshot contains every provider from `https://models.dev/api.json`
at its recorded timestamp. It stores provider metadata and model counts, not
the full model definitions. The MIT notice is in `assets/models.dev.LICENSE`.

The page initially reads the last validated cache or bundled snapshot. An
explicit **Refresh catalog** updates it. Browsing details may cache the selected
provider's logo while live mode is on. Logos have a generic fallback; QML loads
only local images. These operations never discover accounts or query quotas.

Disposable metadata, logos and new-provider usage caches live under
`$XDG_CACHE_HOME/k4/agents`, or `~/.cache/k4/agents`. Failed refreshes keep the
last good catalog. The page shows its source and timestamp.

To regenerate the bundled snapshot from the public API:

```sh
python3 -B tools/agents_catalog.py --update-snapshot plugins/Agents/assets/models-dev-providers.json
```

## Helper and verification

```sh
python3 -B tools/agents.py --providers claude,codex --offline
python3 -B tools/agents.py --providers opencode-go,zai-coding-plan
python3 -B tools/agents.py --providers ''
python3 -B tools/agents.py --catalog --offline
python3 -B tools/agents.py --catalog --refresh-catalog
python3 -B tools/test_agents.py
python3 -B tools/test_agents_ui.py
```

`--sin-red` remains a compatibility alias for `--offline`. Unknown provider
IDs and unknown flags are rejected. The existing `agentes`/`limites` JSON
contract remains stable. New adapters join the registry in `tools/agents.py`;
catalog membership alone does not enable tracking.

Python tests use synthetic accounts and mocked HTTP. The QML suite uses a
private home, conflicting legacy/current state fixtures, and a delayed worker
that deliberately returns after cancellation to exercise stale-result handling.
