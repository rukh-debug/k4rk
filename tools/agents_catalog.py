#!/usr/bin/env python3
"""Public models.dev metadata, independent of account/credential discovery.

The shipped snapshot makes the entire provider picker available on first use
offline. Explicit refresh replaces only validated metadata; failed requests
leave the last good snapshot intact. No quota endpoint comes from this data.
"""

import argparse
import json
import os
import re
import tempfile
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlparse
from xml.etree import ElementTree

SOURCE = "https://models.dev/api.json"
SNAPSHOT = Path(__file__).resolve().parent.parent / "plugins/Agents/assets/models-dev-providers.json"
MAX_JSON_BYTES = 32 * 1024 * 1024
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")


def cache_directory():
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "k4/agents"


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def atomic_bytes(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
            temporary = handle.name
            handle.write(content)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def atomic_json(path, data):
    atomic_bytes(path, (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode())


class NoRedirect(urllib.request.HTTPRedirectHandler):
    # Quota requests carry credentials. Never forward them to a new host;
    # fixed public catalog/logo URLs do not need redirects either.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request_bytes(url, headers=None, maximum=MAX_JSON_BYTES):
    request = urllib.request.Request(url, headers={"User-Agent": "k4-agents/1.0", "Accept": "application/json", **(headers or {})})
    with urllib.request.build_opener(NoRedirect).open(request, timeout=6) as response:
        raw = response.read(maximum + 1)
    if len(raw) > maximum:
        raise ValueError("Response too large")
    return raw


def request_json(url, headers=None):
    data = json.loads(request_bytes(url, headers))
    if not isinstance(data, dict):
        raise ValueError("Expected an object")
    return data


def safe_url(value):
    if not isinstance(value, str):
        return ""
    try:
        parsed = urlparse(value)
        return value if parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password else ""
    except ValueError:
        return ""


def normalize_provider(ident, raw):
    if not isinstance(ident, str) or not ID_PATTERN.fullmatch(ident) or not isinstance(raw, dict):
        raise ValueError("Invalid provider")
    name, env = raw.get("name"), raw.get("env")
    if not isinstance(name, str) or not name.strip() or not isinstance(env, list):
        raise ValueError("Invalid provider metadata")
    # Some providers publish names beginning with a digit (302AI_API_KEY).
    # These are metadata to display/copy, never shell code to execute.
    if any(not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_]+", key) for key in env):
        raise ValueError("Invalid environment variable name")
    return {"id": ident, "name": name, "env": env, "doc": safe_url(raw.get("doc")),
            "api": safe_url(raw.get("api")), "modelCount": len(raw.get("models", {})) if "models" in raw else raw.get("modelCount", 0)}


def normalize(payload):
    if not isinstance(payload, dict) or not payload:
        raise ValueError("Empty provider catalog")
    rows = [normalize_provider(ident, raw) for ident, raw in payload.items()]
    return sorted(rows, key=lambda row: (row["name"].casefold(), row["id"]))


def valid_snapshot(data):
    try:
        if not isinstance(data, dict) or data.get("version") != 1 or not data.get("providers"):
            return None
        rows = data["providers"]
        normalized = normalize({row["id"]: row for row in rows})
        if len(normalized) != len(rows):
            return None
        return dict(data, providers=normalized)
    except (ValueError, TypeError, KeyError, AttributeError):
        return None


def cache_logo(ident):
    if not ID_PATTERN.fullmatch(ident):
        return
    target = cache_directory() / "logos" / (ident + ".svg")
    if target.exists():
        return
    try:
        raw = request_bytes("https://models.dev/logos/" + ident + ".svg", maximum=128 * 1024)
        root = ElementTree.fromstring(raw)
        if root.tag.split("}")[-1] != "svg":
            return
        # Provider glyphs use currentColor. A white cached version remains
        # legible on k4's dark surfaces; no remote resources enter QML.
        for node in root.iter():
            if node.tag.split("}")[-1] not in ("svg", "g", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "defs", "clipPath", "title", "desc"):
                return
            for key, value in list(node.attrib.items()):
                if "href" in key or key.startswith("on") or key == "style":
                    return
                node.set(key, value.replace("currentColor", "#ffffff"))
        root.set("fill", root.get("fill", "#ffffff"))
        atomic_bytes(target, ElementTree.tostring(root))
    except (OSError, ValueError, ElementTree.ParseError):
        pass


def load_catalog(snapshot=None, refresh=False, logo=None):
    cached_path = cache_directory() / "models-dev-providers.json"
    bundled = valid_snapshot(read_json(snapshot or SNAPSHOT))
    saved = valid_snapshot(read_json(cached_path))
    data = saved or bundled
    origin = "cache" if saved else "bundled"
    error = ""
    if refresh:
        try:
            rows = normalize(request_json(SOURCE))
            # A truncated but valid JSON response must not erase the catalog.
            if data and len(rows) < len(data["providers"]) // 2:
                raise ValueError("Incomplete catalog")
            data = {"version": 1, "source": SOURCE, "updated": time.time(), "providers": rows}
            origin = "live"
            try:
                atomic_json(cached_path, data)
            except OSError:
                error = "Catalog loaded, but its cache could not be saved"
        except (OSError, ValueError, TypeError):
            error = "Catalog refresh failed; showing the last available snapshot"
    if data is None:
        data = {"version": 1, "source": SOURCE, "providers": []}
        error = "No provider catalog available; refresh when online"
    known = {row["id"] for row in data["providers"]}
    if logo in known:
        cache_logo(logo)
    rows = []
    for row in data["providers"]:
        image = cache_directory() / "logos" / (row["id"] + ".svg")
        rows.append(dict(row, logo=image.as_uri() if image.is_absolute() and image.exists() else ""))
    return dict(data, providers=rows, origin=origin, error=error)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Regenerate the bundled public provider snapshot")
    parser.add_argument("--update-snapshot", type=Path, required=True)
    args = parser.parse_args()
    rows = normalize(request_json(SOURCE))
    atomic_json(args.update_snapshot, {"version": 1, "source": SOURCE, "updated": time.time(), "providers": rows})
    print("Saved", len(rows), "providers")
