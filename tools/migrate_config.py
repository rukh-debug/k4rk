#!/usr/bin/env python3
"""Move the consolidated v1 document to settings-only v2 storage.

This transition reads the current authoritative document, never rescans retired
pre-config.json files. Missing v2 configuration means a fresh/reset settings file.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import config_store as store
from config_schema import (SHELL_DEFAULTS, LOCAL_SHELL_DEFAULTS, OBSOLETE_PLUGINS,
                           NATIVE_IDS, OPENWEBUI_SETTINGS, WALLPAPER_SETTINGS)


def report_path(version=2):
    return store.state_root() / "migrations" / ("config-v%d.json" % version)


def migrate(dry_run=False):
    with store.locked():
        if not dry_run:
            store.recover_unlocked()
        elif store.journal_path().exists():
            raise ValueError("Recover the pending storage transaction before a dry run")
        old = store.read_file(store.config_path())
        if old is None:
            report = dict(version=2, migrated=False, removedPlugins=[], conflicts=[])
            if not dry_run:
                documents = {store.config_path(): store.empty()}
                if not report_path().exists():
                    documents[report_path()] = report
                store.commit_unlocked(documents)
            return report
        if not isinstance(old, dict):
            raise ValueError("Configuration must be an object")
        if old.get("schemaVersion") == 2:
            store.validate(old)
            # The report is diagnostic bookkeeping, never a runtime dependency.
            return dict(version=2, migrated=False)
        if old.get("schemaVersion") != 1:
            raise ValueError("Unsupported configuration version")
        for section in ("shell", "features", "plugins", "cache"):
            if not isinstance(old.get(section, {}), dict):
                raise ValueError("Invalid v1 section: " + section)
        store.check_values(old)
        settings = store.empty()
        # A deliberately installed replacement with an old id is still a real
        # plugin. Temporary manifest/dependency failures must not erase it.
        retired_ids = {ident for ident in OBSOLETE_PLUGINS if not (store.plugin_root() / ident).exists()}
        documents = {}
        conflicts = []
        report = dict(version=2, migrated=True, sourceDigest=hashlib.sha256(store.encode(old).encode()).hexdigest(),
                      removedPlugins=[], conflicts=conflicts)

        def stage(path, value):
            path = Path(path)
            # Existing local state may have been updated independently. Keep it
            # and preserve the conflicting import in the private transition record.
            existing = store.read_file(path)
            if existing is not None and existing != value:
                conflicts.append(dict(path=str(path), imported=value))
                return
            documents[path] = copy.deepcopy(value)

        def local(logical, value):
            if logical[:1] == ["plugins"] and len(logical) == 3 and logical[2] == "installation":
                if not (store.plugin_root() / logical[1] / "plugin.json").is_file():
                    archive = store.state_root() / "retired/installations.json"
                    documents.setdefault(archive, {})[logical[1]] = value
                    return
            path, relative = store.route(logical)
            if path == store.config_path():
                raise ValueError("Migration tried to route private data into settings")
            draft = documents.get(path, {})
            documents[path] = store.assign(draft, relative, value)

        shell = old.get("shell", {})
        for key in SHELL_DEFAULTS:
            if key in shell:
                settings["shell"][key] = copy.deepcopy(shell[key])
        for key in LOCAL_SHELL_DEFAULTS:
            if key in shell:
                local(["shell", key], shell[key])
        if not shell.get("pillMigrated") and "trayInPill" in shell:
            hidden = list(settings["shell"].get("pillHiddenItems", ["tray"]))
            hidden = [item for item in hidden if item != "tray"] if shell["trayInPill"] else list(dict.fromkeys(hidden + ["tray"]))
            settings["shell"]["pillHiddenItems"] = hidden
        # Host migration flags and the obsolete tray switch have no readers in
        # the new format. Their effect is already represented by pillHiddenItems.
        for key in ("quickAccess", "panelOrder", "panelHiddenBlocks"):
            if key in settings["shell"]:
                settings["shell"][key] = [value for value in settings["shell"][key]
                    if str(value).split(".")[0] not in retired_ids]
        for key in ("islandPlacements", "independentIslands", "popupSizes"):
            if key in settings["shell"]:
                settings["shell"][key] = {ident: value for ident, value in settings["shell"][key].items()
                                           if ident not in retired_ids}
        for feature, value in old.get("features", {}).items():
            if feature == "wallpaper":
                for key, item in value.items():
                    if key in WALLPAPER_SETTINGS:
                        settings["features"].setdefault("wallpaper", {})[key] = item
                    else:
                        local(["features", "wallpaper", key], item)
            elif feature == "monitors":
                local(["features", "monitors"], value)
            else:
                stage(store.state_root() / "retired" / (feature + ".json"), value)
        for ident, plugin in old.get("plugins", {}).items():
            if ident in retired_ids:
                report["removedPlugins"].append(ident)
                continue
            shared = {}
            if ident not in NATIVE_IDS and "enabled" in plugin:
                shared["enabled"] = plugin["enabled"]
            if ident in ("agents", "system"):
                shared["settings"] = dict(plugin.get("state", {}), **plugin.get("settings", {}))
                if ident == "system":
                    combined = shared["settings"].pop("chip", None)
                    if combined is not None:
                        for key in ("chipCpu", "chipRam"):
                            shared["settings"].setdefault(key, combined)
            if ident == "hola" and isinstance(plugin.get("state"), dict):
                state = plugin["state"]
                preferences = plugin.get("settings", {})
                shared["settings"] = {"greetOnOpen": preferences.get("greetOnOpen", state.get("saludar", True))}
            for name, value in plugin.items():
                if name == "enabled":
                    continue
                if ident in ("agents", "system") and name in ("state", "settings"):
                    continue
                if ident == "hola" and name == "state":
                    local(["plugins", ident, "state"], {"visits": value.get("visits", value.get("visitas", 0)),
                                                         "recipient": value.get("recipient", value.get("aQuien", ""))})
                    continue
                if ident == "hola" and name == "settings" and "settings" in shared:
                    continue
                if name == "settings" and ident not in NATIVE_IDS:
                    if ident == "openwebui":
                        shared[name] = {key: item for key, item in value.items() if key in OPENWEBUI_SETTINGS}
                        profile = {key: item for key, item in value.items() if key not in OPENWEBUI_SETTINGS}
                        if profile:
                            local(["plugins", ident, "profile"], profile)
                    else:
                        shared[name] = value
                elif name != "settings" or ident in NATIVE_IDS:
                    # Replaced native enablement is removed; residual documents
                    # are local state, never interpreted as current preferences.
                    local(["plugins", ident, "previous-settings" if name == "settings" else name], value)
            if shared and ident not in NATIVE_IDS:
                settings["plugins"][ident] = shared
        cache = old.get("cache", {})
        if "pluginCatalog" in cache:
            catalog = copy.deepcopy(cache["pluginCatalog"])
            if isinstance(catalog, dict) and isinstance(catalog.get("plugins"), list):
                catalog["plugins"] = [plugin for plugin in catalog["plugins"]
                                      if plugin.get("id") not in retired_ids | NATIVE_IDS]
            local(["cache", "pluginCatalog"], catalog)
        for owner, values in cache.items():
            if owner == "pluginCatalog":
                continue
            for name, value in values.items():
                local(["cache", owner, name], value)
        retired = {key: value for key, value in old.get("retired", {}).items()
                   if key not in ("savedGame", "tokenRewards", "usageOffsets", "settingsPages")}
        if retired:
            stage(store.state_root() / "retired/config-v1.json", retired)
        if old.get("migration"):
            stage(report_path(1), old["migration"])
        # A server profile and its conversation must not be mixed with a
        # different, newer local account's documents during conflict recovery.
        chat_paths = [store.state_root() / "plugins/openwebui" / name
                      for name in ("profile.json", "state.json")]
        if any(path in documents and store.read_file(path) is not None
               and store.read_file(path) != documents[path] for path in chat_paths):
            for path in chat_paths:
                if path in documents:
                    conflicts.append(dict(path=str(path), imported=documents.pop(path)))
        # Apply destination-wins to documents assembled from several fields.
        for path, value in list(documents.items()):
            existing = store.read_file(path)
            if existing is not None and existing != value:
                conflicts.append(dict(path=str(path), imported=value))
                del documents[path]
        if store.nested(settings, ["plugins", "openwebui", "settings", "rememberHistory"]) is False:
            history = store.state_root() / "plugins/openwebui/state.json"
            documents[history] = {}
            conflicts[:] = [conflict for conflict in conflicts if conflict["path"] != str(history)]
        store.validate(settings)
        documents[store.config_path()] = settings
        documents[report_path()] = report
        if not dry_run:
            store.commit_unlocked(documents)
        return report


def retry_credentials():
    import credentials
    report = store.read_file(report_path(1), {})
    remaining = []
    for name in report.get("pendingCredentials", []):
        path = Path(name)
        try:
            value = json.loads(path.read_text())
            if path.name == "claves.json":
                entries = [("ssh", alias, secret) for alias, secret in value.items()]
            elif path.parent.name == "openwebui" and value.get("apiToken"):
                entries = [("openwebui", str(value.get("baseUrl", "")).rstrip("/"), value["apiToken"])]
            else:
                remaining.append(name)
                continue
            for plugin, account, secret in entries:
                credentials.request("set", plugin, account, secret)
                if credentials.request("get", plugin, account) != secret:
                    raise RuntimeError("Credential verification failed")
        except (OSError, ValueError, RuntimeError):
            remaining.append(name)
    report["pendingCredentials"] = remaining
    with store.locked():
        store.recover_unlocked()
        store.commit_unlocked({report_path(1): report})
    return report


def retire():
    report = store.read_file(report_path(1), {})
    pending = set(report.get("pendingCredentials", []))
    for item in report.get("imported", []):
        path = Path(item["path"])
        if str(path) in pending or path.name in ("k4term.conf", "confirmed.lua"):
            continue
        if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == item["digest"]:
            path.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--retire", action="store_true")
    parser.add_argument("--retry-credentials", action="store_true")
    args = parser.parse_args()
    report = migrate(args.dry_run)
    if args.retry_credentials and not args.dry_run:
        report = retry_credentials()
    # Reports can contain privately preserved conflicts. Print counts, not data.
    print(json.dumps({"version": report.get("version"), "migrated": report.get("migrated", False),
                      "removedPlugins": report.get("removedPlugins", []),
                      "conflicts": len(report.get("conflicts", [])),
                      "pendingCredentials": len(report.get("pendingCredentials", []))}, indent=2))
    if args.retire and not args.dry_run:
        retire()
