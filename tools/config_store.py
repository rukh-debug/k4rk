#!/usr/bin/env python3
"""Transactional storage with a settings-only config and owner-local state/cache.

All supported readers take the same lock and recover interrupted cross-file
transactions before returning data. Only read()/copy export shareable settings.
"""
import argparse
import copy
import fcntl
import hashlib
import json
import os
import re
import selectors
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

from config_schema import (SHELL_DEFAULTS, LOCAL_SHELL_DEFAULTS, OBSOLETE_PLUGINS,
                           WALLPAPER_SETTINGS, validate_sections)

VERSION = 2
SECRET_FIELDS = {"password", "passphrase", "apitoken", "apikey", "accesstoken",
                 "refreshtoken", "privatekey", "clientsecret", "authorization",
                 "contrasena", "contrasenas", "draftpassword", "draftapikey", "token"}


def config_path():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "k4/config.json"


def state_root():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "k4"


def cache_root():
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "k4"


def plugin_root():
    return config_path().parent / "plugins"


def empty():
    return dict(schemaVersion=VERSION, shell={}, features={}, plugins={})


def check_values(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ValueError("Storage keys must be strings")
            if "".join(c for c in key.casefold() if c.isalnum()) in SECRET_FIELDS:
                raise ValueError("Credentials belong in the system keyring")
            check_values(child)
    elif isinstance(value, list):
        for child in value:
            check_values(child)


def validate(data):
    if not isinstance(data, dict) or type(data.get("schemaVersion")) is not int or data["schemaVersion"] != VERSION:
        raise ValueError("Unsupported config.json schemaVersion; run the configuration migration")
    if set(data) != {"schemaVersion", "shell", "features", "plugins"}:
        raise ValueError("config.json may contain only shareable settings")
    for key in ("shell", "features", "plugins"):
        if not isinstance(data[key], dict):
            raise ValueError("Invalid settings section: " + key)
    check_values(data)
    validate_sections(data)
    encode(data)
    return data


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"


def read_file(path, default=None):
    try:
        def invalid_constant(value):
            raise ValueError("Non-finite JSON value: " + value)
        return json.loads(Path(path).read_text(encoding="utf-8"), parse_constant=invalid_constant)
    except FileNotFoundError:
        return copy.deepcopy(default)


@contextmanager
def locked():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()) / ("k4-config-" + str(os.getuid()))
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    if runtime.is_symlink() or runtime.stat().st_uid != os.getuid():
        raise OSError("Invalid configuration lock directory")
    os.chmod(runtime, 0o700)
    identity = hashlib.sha256(str(config_path().absolute()).encode()).hexdigest()
    fd = os.open(runtime / (identity + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def sync_directory(path):
    fd = os.open(path, os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path, content):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix="." + path.name + ".", delete=False) as stream:
            temporary = stream.name
            os.fchmod(stream.fileno(), 0o600)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def journal_path():
    return state_root() / "transactions/pending.json"


def replace_text(path, text):
    if text is None:
        if path.exists():
            path.unlink()
            sync_directory(path.parent)
    else:
        atomic_write(path, text)


def recover_unlocked():
    journal = read_file(journal_path())
    if journal is None:
        return
    if journal.get("version") != 1 or journal.get("phase") not in ("commit", "rollback"):
        raise ValueError("Unrecognized storage recovery journal")
    field = "after" if journal["phase"] == "commit" else "before"
    for entry in journal["entries"]:
        replace_text(Path(entry["path"]), entry[field])
    journal_path().unlink()
    sync_directory(journal_path().parent)


def commit_unlocked(documents):
    """Commit owned documents. Caller holds locked(); None deletes a document.

    A prepared journal rolls forward after process death. A caught write error
    records rollback before restoring prior bytes, preserving the failed-save
    contract even when directory fsync failed after an atomic rename.
    """
    entries = []
    for path, value in documents.items():
        path = Path(path)
        try:
            before = path.read_text() if path.exists() else None
        except UnicodeDecodeError:
            if not path.is_relative_to(cache_root()):
                raise
            before = None
        if value is not None:
            check_values(value)
        after = encode(value) if value is not None else None
        if before is not None and value is not None:
            try:
                if json.loads(before) == value:
                    continue
            except ValueError:
                pass
        if before != after:
            entries.append(dict(path=str(path), before=before, after=after))
    if not entries:
        return
    # Local history is removed before publishing a preference that disables it.
    entries.sort(key=lambda entry: entry["path"] == str(config_path()))
    if len(entries) == 1:
        entry = entries[0]
        try:
            replace_text(Path(entry["path"]), entry["after"])
        except OSError:
            replace_text(Path(entry["path"]), entry["before"])
            raise
        return
    journal = dict(version=1, phase="commit", entries=entries)
    try:
        atomic_write(journal_path(), encode(journal))
        for entry in entries:
            replace_text(Path(entry["path"]), entry["after"])
    except OSError:
        journal["phase"] = "rollback"
        atomic_write(journal_path(), encode(journal))
        recover_unlocked()
        raise
    journal_path().unlink()
    sync_directory(journal_path().parent)


def route(path):
    """Map logical ownership to physical storage; never infer from values."""
    if not isinstance(path, list) or not path or any(not isinstance(k, str) or not k for k in path):
        raise ValueError("Invalid storage path")
    if path[0] == "shell":
        if len(path) > 1 and path[1] in LOCAL_SHELL_DEFAULTS:
            return state_root() / "shell.json", path[1:]
        return config_path(), path
    if path[0] == "features" and len(path) > 1:
        if path[1] == "monitors":
            return state_root() / "monitors/profile.json", path[2:]
        if path[1] == "wallpaper" and len(path) > 2 and path[2] not in WALLPAPER_SETTINGS:
            return state_root() / "wallpaper.json", path[2:]
        return config_path(), path
    if path[0] == "plugins" and len(path) >= 2:
        ident = path[1]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", ident):
            raise ValueError("Invalid plugin id")
        if len(path) == 2 or path[2] in ("enabled", "settings"):
            return config_path(), path
        name = path[2]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", name):
            raise ValueError("Invalid plugin state name")
        if name == "installation":
            return plugin_root() / ident / ".installation.json", path[3:]
        return state_root() / "plugins" / ident / (name + ".json"), path[3:]
    if path[0] == "cache":
        if len(path) > 1 and path[1] == "pluginCatalog":
            return cache_root() / "plugins/catalog.json", path[2:]
        if len(path) >= 3 and all(re.fullmatch(r"[A-Za-z0-9_-]+", k) for k in path[1:3]):
            return cache_root() / path[1] / (path[2] + ".json"), path[3:]
    raise ValueError("Unknown storage owner")


def nested(value, path, default=None):
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return copy.deepcopy(default)
        value = value[key]
    return copy.deepcopy(value)


def assign(document, path, value=None, delete=False, if_absent=False):
    if not path:
        return None if delete else copy.deepcopy(value)
    parent = document
    for key in path[:-1]:
        parent = parent.setdefault(key, {})
        if not isinstance(parent, dict):
            raise ValueError("Storage path crosses a non-object value")
    if delete:
        parent.pop(path[-1], None)
    elif not if_absent or path[-1] not in parent:
        parent[path[-1]] = copy.deepcopy(value)
    return document


def read_unlocked():
    return validate(read_file(config_path(), empty()))


def read():
    with locked():
        recover_unlocked()
        return read_unlocked()


def get(path, default=None):
    location, relative = route(path)
    with locked():
        recover_unlocked()
        try:
            data = read_unlocked() if location == config_path() else read_file(location, {})
        except (OSError, ValueError):
            if location.is_relative_to(cache_root()):
                return copy.deepcopy(default)
            raise
        return nested(data, relative, default)


def etag(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, allow_nan=False).encode()).hexdigest()


def transaction(operations, expected_digest=None):
    with locked():
        recover_unlocked()
        settings = read_unlocked()
        if expected_digest is not None and etag(settings) != expected_digest:
            raise ValueError("Configuration changed; reload before retrying")
        documents = {}
        for operation in operations:
            location, relative = route(operation["path"])
            if location not in documents:
                try:
                    documents[location] = copy.deepcopy(settings) if location == config_path() else read_file(location, {})
                except ValueError:
                    if not location.is_relative_to(cache_root()):
                        raise
                    documents[location] = {}
            documents[location] = assign(documents[location], relative, operation.get("value"),
                operation.get("delete", False), operation.get("ifAbsent", False))
        if config_path() in documents:
            settings = validate(documents[config_path()])
        # Even a direct settings transaction must honor the no-history setting.
        if nested(settings, ["plugins", "openwebui", "settings", "rememberHistory"]) is False:
            history = state_root() / "plugins/openwebui/state.json"
            if history.exists() or history in documents:
                documents[history] = {}
        for location, value in documents.items():
            if value is not None:
                check_values(value)
        commit_unlocked(documents)
        return settings


def put(path, value):
    return transaction([dict(path=path, value=value)])


def remove(path):
    return transaction([dict(path=path, delete=True)])


def local_files():
    yield state_root() / "shell.json", ["shell"]
    yield state_root() / "wallpaper.json", ["features", "wallpaper"]
    yield state_root() / "monitors/profile.json", ["features", "monitors"]
    yield cache_root() / "plugins/catalog.json", ["cache", "pluginCatalog"]
    for path in sorted((state_root() / "plugins").glob("*/*.json")):
        if path.stem in ("settings", "enabled", "installation"):
            continue
        yield path, ["plugins", path.parent.name, path.stem]


def snapshot():
    with locked():
        recover_unlocked()
        data = read_unlocked()
        history = state_root() / "plugins/openwebui/state.json"
        if nested(data, ["plugins", "openwebui", "settings", "rememberHistory"]) is False and history.exists():
            commit_unlocked({history: {}})
        local = {}
        errors = {}
        for path, logical in local_files():
            try:
                value = read_file(path)
                check_values(value)
            except (OSError, ValueError):
                errors["/".join(logical)] = "Could not read this local state document"
                continue
            if value is not None:
                if logical == ["shell"] and isinstance(value, dict):
                    value = {key: child for key, child in value.items() if key in LOCAL_SHELL_DEFAULTS}
                if logical == ["features", "wallpaper"] and isinstance(value, dict):
                    value = {key: child for key, child in value.items() if key not in WALLPAPER_SETTINGS}
                local = assign(local, logical, value)
        return dict(data=data, local=local, localErrors=errors, etag=etag(data))


def remove_plugin_settings(ident):
    """Forget preferences/references only after an explicit uninstall succeeds."""
    with locked():
        recover_unlocked()
        settings = read_unlocked()
        settings["plugins"].pop(ident, None)
        shell = settings["shell"]
        for key in ("quickAccess", "panelOrder", "panelHiddenBlocks", "pillOrder", "pillHiddenItems"):
            if key in shell:
                shell[key] = [value for value in shell[key] if value != ident and not str(value).startswith(ident + ".")]
        for key in ("islandPlacements", "popupSizes", "independentIslands"):
            if isinstance(shell.get(key), dict):
                shell[key].pop(ident, None)
        validate(settings)
        documents = {config_path(): settings}
        catalog_path = cache_root() / "plugins/catalog.json"
        try:
            catalog = read_file(catalog_path)
        except ValueError:
            catalog = None
        if isinstance(catalog, dict) and isinstance(catalog.get("plugins"), list):
            catalog["plugins"] = [plugin for plugin in catalog["plugins"]
                                  if isinstance(plugin, dict) and plugin.get("id") != ident]
            documents[catalog_path] = catalog
        commit_unlocked(documents)


def initialize():
    from migrate_config import migrate
    migrate()
    data = read()
    missing = [dict(path=["shell", key], value=value, ifAbsent=True)
               for key, value in SHELL_DEFAULTS.items() if key not in data["shell"]]
    transaction(missing)
    return read()


def fingerprint():
    paths = [config_path(), journal_path()] + [path for path, _ in local_files()]
    result = []
    for path in paths:
        try:
            stat = path.stat()
            result.append((str(path), stat.st_ino, stat.st_mtime_ns, stat.st_size))
        except FileNotFoundError:
            pass
    return result


def emit(value):
    print(json.dumps(value, ensure_ascii=False, allow_nan=False), flush=True)


def serve():
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ)
    previous = previous_outputs = previous_fingerprint = None
    pending = b""
    try:
        initialize()
    except (OSError, ValueError) as error:
        emit(dict(error=str(error)))
    while True:
        if selector.select(0.25):
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                break
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                request = {}
                try:
                    request = json.loads(line)
                    transaction(request["operations"], request.get("expectedDigest"))
                    previous = snapshot()
                    emit(dict(previous, id=request.get("id")))
                except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
                    emit(dict(id=request.get("id") if isinstance(request, dict) else None, error=str(error)))
        current_fingerprint = fingerprint()
        if previous is not None and previous_fingerprint == current_fingerprint:
            continue
        try:
            current = snapshot()
            previous_fingerprint = current_fingerprint
            if current != previous:
                emit(dict(current, defaults=SHELL_DEFAULTS, localDefaults=LOCAL_SHELL_DEFAULTS))
                previous = current
            outputs = [get(["plugins", "terminal", "settings"], {}), get(["plugins", "ssh", "hosts"], {}),
                       get(["features", "monitors"], {})]
            if outputs != previous_outputs:
                from config_outputs import terminal, ssh, monitor_compatibility
                try:
                    terminal()
                    ssh()
                    monitor_compatibility()
                    previous_outputs = outputs
                except (OSError, ValueError) as error:
                    emit(dict(outputError="Could not refresh compatibility output: " + str(error)))
        except (OSError, ValueError) as error:
            emit(dict(error=str(error)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("init", "read", "transact", "serve", "copy"))
    args = parser.parse_args()
    try:
        if args.action == "serve":
            serve()
        elif args.action == "copy":
            subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=encode(read()),
                           text=True, check=True, timeout=10)
        elif args.action == "transact":
            request = json.load(sys.stdin)
            emit(transaction(request["operations"], request.get("expectedDigest")))
        else:
            emit(initialize() if args.action == "init" else read())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print("k4 storage: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
