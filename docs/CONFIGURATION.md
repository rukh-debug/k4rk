# Shareable configuration and local data

`$XDG_CONFIG_HOME/k4/config.json` (normally `~/.config/k4/config.json`) contains
**shareable appearance and behavior settings only**. Settings → General →
Configuration displays its resolved path. **Copy configuration** copies the
validated settings JSON; **Copy file path** copies just its location.

## Settings schema

The only top-level keys are `schemaVersion` (currently 2), `shell`, `features`,
and `plugins`. There are no revision counters, catalog snapshots, migration
records, private profiles, or histories in this file.

- `shell`: layout, fonts, sounds, visibility, popup placement/sizes, night-light
  mode and temperature, and pinned application shortcuts.
- `features.wallpaper`: transition and palette scheme preferences.
- `plugins.<id>.enabled`: explicitly selected plugin enablement.
- `plugins.<id>.settings`: the plugin's shareable preferences. Absent settings
  follow defaults; a plugin does not need an entry simply because it is installed.

`quickAccess` is the ordered list of pinned applications beside **All apps** in
the Control Centre. The application grid's pin button edits it. Unavailable pins
are not drawn. Uninstall removes the plugin's pin, while disabling it preserves
the preference. Removed first-party plugins are cleaned during migration, not
reintroduced through defaults.

## Owner-local storage

All directories honor their XDG overrides.

| Data | Default location |
| --- | --- |
| Plugin named state | `~/.local/state/k4/plugins/<id>/<name>.json` |
| OpenWebUI conversations | `~/.local/state/k4/plugins/openwebui/state.json` |
| OpenWebUI server, login drafts, model selection and pin lists | `~/.local/state/k4/plugins/openwebui/profile.json` |
| SSH connection profiles and metadata | Named files under `~/.local/state/k4/plugins/ssh/` |
| Confirmed monitor profile/integration | `~/.local/state/k4/monitors/profile.json` |
| Wallpaper selection and library paths | `~/.local/state/k4/wallpaper.json` |
| Location and temporary night-light overrides | `~/.local/state/k4/shell.json` |
| Agent usage and provider catalog caches | `~/.cache/k4/agents/` |
| Combined plugin catalog cache | `~/.cache/k4/plugins/catalog.json` |
| Plugin manifest/source | The installed plugin's directory |
| Installation provenance | `.installation.json` beside the installed manifest |
| Transition reports | `~/.local/state/k4/migrations/` |
| Preserved unrelated retired data | `~/.local/state/k4/retired/` |
| Interrupted cross-file transactions | `~/.local/state/k4/transactions/` |

Cache refreshes, conversation updates and installation metadata writes do not
rewrite `config.json`. Wallpapers, screenshots, recordings, logs, image caches
and plugin code remain ordinary files. Clipboard history retains its own storage.

Credentials are never stored in any of these JSON domains. `K4.Credential` uses
desktop Secret Service, with session-only fallback when unavailable. SSH private
keys remain in existing SSH files/agents. Provider-owned credential stores remain
external. Plugin authors must use the settings/state APIs according to the data's
purpose and must not hide credentials in arbitrary text or unrelated field names.

## Persistence API

Use `K4.PluginSettings` for shareable preferences and `K4.PluginState` for local
state. The existing `K4.Guardado` contract remains supported: `ajustes`/`settings`
addresses preferences; `estado`/`state` and other names address local state.
Agents and System explicitly use PluginSettings because their old `state`
documents contained preference values.

The host and standalone Python helpers share one transaction implementation.
Writes reread the relevant documents under a shared lock and use atomic rename
and fsync. Cross-file transactions have a private recovery journal. Supported
readers recover a pending transaction before exposing data; a caught write failure
rolls back all affected documents. A crashed commit rolls forward on recovery.
This preserves the guarantee that disabling remembered history clears the saved
conversation together with the preference update.

Settings conflict detection uses an in-memory digest (`expectedDigest` in CLI
transactions), not a changing revision field in the JSON. External file changes
are observed. Malformed settings are never replaced with defaults. Corrupt caches
can be rebuilt; malformed local plugin state is reported without breaking valid
shared settings or silently overwriting the damaged document.

## Plugin lifecycle

Installation/update records provenance with the plugin, not in configuration.
Disabling or temporarily failing to load a plugin preserves preferences. An
explicit successful uninstall removes its config namespace, pinned shortcuts,
layout references and cached catalog entry. Saved state remains local unless
state removal was also requested. Startup does not blindly delete settings for
missing plugins: a shared config may intentionally preconfigure future installs.

## Migration

```sh
python3 tools/migrate_config.py --dry-run
python3 tools/migrate_config.py
```

The bounded v1→v2 transition reads the current consolidated file. It moves private
data, caches, provenance and bookkeeping to their owners, moves real Agents/System
preferences into `settings`, and removes obsolete first-party plugin namespaces
and references, preserving installed replacements even if their manifests or
dependencies are temporarily unavailable. False, zero and empty preferences are preserved. Existing local
destination data wins a conflict; the displaced import is preserved in the private
transition report. The CLI prints counts, not profile or conversation contents.

Migration commits destination files before replacing configuration and recovers
after interruption. Schema v2 prevents repeat historical import even when its
report is missing. Deleting config means reset to defaults: startup never scans
retired pre-config files to resurrect old values. Pending historical credential
transfers can be retried with `--retry-credentials`; `--retire` only removes
unchanged, successfully imported historical sources using the separate v1 report.

## Generated external formats

Native k4term preferences, SSH includes, monitor Lua and the live theme export
remain one-way generated output. Terminal preferences come from shared settings;
SSH and monitor definitions come from local profiles. Existing installed monitor
hooks continue to receive generated `confirmed.lua` output. These formats are not
read back as settings after transition and contain no credentials.
