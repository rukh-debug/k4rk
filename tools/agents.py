#!/usr/bin/env python3
"""Agent subscription limits in one place.

Claude Code and Codex enforce time windows — five hours, a week, and for
Claude a separate model quota — but each describes them differently and
stores them in its own corner of the disk. Normalize them for the bar.

Sources:
  · Claude: ask the server with Claude Code's existing token. This reads the
    user's own account without spending quota, just like its /usage command.
  · Codex: its app-server account API supplies live subscription limits;
    ~/.codex/sessions rollouts remain the offline fallback.
  · Coding-plan providers: read-only HTTPS quota endpoints.

Claude needed the live query: cachedUsageUtilization in ~/.claude.json is
updated infrequently. On this machine it once said 6% while the server said
24%, lagging by 131 minutes with an active session. A quota monitor that is
two hours behind cannot answer whether there is enough left for the next task.

The CLI cache remains the fallback when offline or when the token is missing
or expired. Each result includes its timestamp and source: an old percentage
presented as current is worse than no data. --offline never sends a request;
--sin-red remains an alias for existing callers. HTTP-only providers then
report no live data. --providers filters before any discovery or disk read.

The existing agentes/limites JSON keys remain the view's wire contract.
Catalog browsing is a separate operation and never discovers credentials.
"""

import argparse
import hashlib
import json
import math
import os
import selectors
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

from agents_catalog import atomic_json, cache_directory, load_catalog, read_json, request_json
import config_store

# Each tool lets an environment variable move its state directory. People
# using that option arrange their disks deliberately: assuming ~/.claude.json
# would work on this machine and fail on theirs. Try paths in order; first wins.
CLAUDE_JSONS = [
    os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".claude.json")
    if os.environ.get("CLAUDE_CONFIG_DIR") else None,
    os.path.expanduser("~/.claude.json"),
]

CODEX_SESIONES = [
    os.path.join(os.environ["CODEX_HOME"], "sessions")
    if os.environ.get("CODEX_HOME") else None,
    os.path.expanduser("~/.codex/sessions"),
]

CLAUDE_CREDENCIALES = [
    os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".credentials.json")
    if os.environ.get("CLAUDE_CONFIG_DIR") else None,
    os.path.expanduser("~/.claude/.credentials.json"),
]

CLAUDE_USO_URL = "https://api.anthropic.com/api/oauth/usage"

# The open view polls every 20 seconds. Asking the server that often would be
# impolite and pointless: percentages do not move that quickly. Reuse a recent
# response so repeated helper invocations make at most one request per minute.
CLAUDE_CACHE_SEGUNDOS = 60
CLAUDE_ESPERA = 6


def primero(rutas, comprueba=os.path.exists):
    """The first path in the list that actually exists."""
    for ruta in rutas:
        if ruta and comprueba(ruta):
            return ruta
    return None

# A newly opened session has not received rate_limits yet, so the newest
# rollout is not necessarily the one containing them. Try this many.
CODEX_ROLLOUTS = 8

# The tail suffices: the last rate_limits is the useful one, and a long
# rollout contains megabytes that need not be parsed in full.
CODEX_COLA = 256 * 1024
CODEX_WAIT = 10
CODEX_CACHE_SECONDS = 60


def epoca(iso):
    """An ISO-8601 instant in epoch seconds, or None."""
    if not isinstance(iso, str) or not iso:
        return None
    try:
        # Python only accepts Z from 3.11 onward; replacing it is cheaper
        # than depending on the installed interpreter version.
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


# ── Claude Code ──────────────────────────────────────────────────────

# The plan arrives as a billing ID. People recognize Max 5× rather than
# default_claude_max_5x.
PLANES_CLAUDE = {
    "default_claude_pro": "Pro",
    "default_claude_max_5x": "Max 5×",
    "default_claude_max_20x": "Max 20×",
}

# weekly_scoped takes the name of its model: Fable today, another tomorrow.
NOMBRES_CLAUDE = {
    "session": ("sesion", "5 hours"),
    "weekly_all": ("semanal", "Weekly"),
}


def limites_claude(uso):
    """Claude's limits in the view's format, including both API generations."""
    if "limits" not in (uso or {}):
        return [quota(key, label, value.get("utilization"), value.get("resets_at"))
                for key, label in (("five_hour", "5 hours"), ("seven_day", "Weekly"),
                                   ("seven_day_sonnet", "Sonnet"), ("seven_day_opus", "Opus"))
                if isinstance(value := (uso or {}).get(key), dict)
                and percentage(value.get("utilization")) is not None]
    limites = []
    for lim in (uso or {}).get("limits") or []:
        if not isinstance(lim, dict):
            continue

        clase = lim.get("kind")
        if clase in NOMBRES_CLAUDE:
            ident, nombre = NOMBRES_CLAUDE[clase]
        else:
            # A model-specific quota uses the model's own name, which is
            # what the person spending it calls it.
            ambito = lim.get("scope") or {}
            modelo = (ambito.get("modelo") or ambito.get("model") or {})
            titulo = modelo.get("display_name") or modelo.get("id")
            if not titulo:
                continue
            ident = str(titulo).lower().replace(" ", "-")
            nombre = titulo

        pct = percentage(lim.get("percent"))
        if pct is None:
            continue
        limites.append({
            "id": ident,
            "nombre": nombre,
            "pct": pct,
            "reinicia": epoca(lim.get("resets_at")),
            "activo": bool(lim.get("is_active")),
        })
    return limites


def token_claude():
    """Claude Code's token, if present on disk and not expired.

    Never refresh it here: refreshing ROTATES the token. The next caller —
    Claude Code, in the middle of a session — would find its own invalid.
    Expired means using the cache and letting the owning tool renew it.
    """
    ruta = primero(CLAUDE_CREDENCIALES)
    if not ruta:
        return None
    try:
        with open(ruta, encoding="utf-8") as f:
            oauth = (json.load(f) or {}).get("claudeAiOauth") or {}
    except (OSError, ValueError):
        return None

    caduca = oauth.get("expiresAt")
    if isinstance(caduca, (int, float)) and caduca / 1000 <= time.time():
        return None
    return oauth.get("accessToken") or None


def uso_en_vivo():
    """Query usage, reusing the last response while it is recent.

    Return (utilization, timestamp) or None. Network failures must fall back
    to the CLI cache rather than leave the view blank.
    """
    # Check the cache first to avoid unnecessary credential reads.
    try:
        guardado = config_store.get(["cache", "agents", "claude-usage"], {})
        if time.time() - guardado.get("time", 0) < CLAUDE_CACHE_SEGUNDOS:
            return guardado.get("usage"), guardado.get("time")
    except (OSError, ValueError):
        guardado = None

    tok = token_claude()
    if not tok:
        return None

    peticion = urllib.request.Request(CLAUDE_USO_URL, headers={
        "Authorization": "Bearer " + tok,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "k4-agents/1.0",
    })
    try:
        with urllib.request.urlopen(peticion, timeout=CLAUDE_ESPERA) as r:
            uso = json.loads(r.read().decode("utf-8"))
    except Exception:                                       # noqa: BLE001
        return None

    if not isinstance(uso, dict) or not any(k in uso for k in ("limits", "five_hour", "seven_day")):
        return None

    cuando = time.time()
    try:
        config_store.put(["cache", "agents", "claude-usage"], {"time": cuando, "usage": uso})
    except (OSError, ValueError):
        pass
    return uso, cuando


def lee_claude(con_red=True):
    """Subscription limits from the server, falling back to the CLI cache."""
    ruta = primero(CLAUDE_JSONS)
    if not ruta:
        return None

    try:
        with open(ruta, encoding="utf-8") as f:
            datos = json.load(f)
    except (OSError, ValueError):
        return None

    cuenta = datos.get("oauthAccount") or {}
    tier = cuenta.get("userRateLimitTier") or cuenta.get("organizationRateLimitTier")
    plan = PLANES_CLAUDE.get(tier, tier or "")

    if con_red:
        vivo = uso_en_vivo()
        if vivo:
            uso, cuando = vivo
            return {"plan": plan, "actualizado": cuando, "fuente": "vivo",
                    "limites": limites_claude(uso)}

    # The CLI's last saved value is updated infrequently. Its timestamp
    # matters especially when it is the only source available.
    cache = datos.get("cachedUsageUtilization")
    if not isinstance(cache, dict):
        return {"limites": [], "plan": plan, "razon": "No data yet — sign in to Claude Code and use it once"}

    fetched = cache.get("fetchedAtMs")
    return {
        "plan": plan,
        "actualizado": fetched / 1000 if isinstance(fetched, (int, float)) else None,
        "fuente": "cache",
        "limites": limites_claude(cache.get("utilization") or {}),
    }


# ── Codex ────────────────────────────────────────────────────────────

def rollouts_recientes(carpeta):
    """Codex rollouts, newest first."""
    encontrados = []
    for raiz, _, ficheros in os.walk(carpeta):
        for nombre in ficheros:
            if nombre.startswith("rollout-") and nombre.endswith(".jsonl"):
                ruta = os.path.join(raiz, nombre)
                try:
                    encontrados.append((os.path.getmtime(ruta), ruta))
                except OSError:
                    continue
    encontrados.sort(reverse=True)
    return [ruta for _, ruta in encontrados[:CODEX_ROLLOUTS]]


def ultimo_limite(ruta):
    """The last rate_limits in a rollout, with its timestamp."""
    try:
        with open(ruta, "rb") as f:
            f.seek(0, os.SEEK_END)
            tamano = f.tell()
            f.seek(max(0, tamano - CODEX_COLA))
            # Starting in the middle leaves a truncated first line;
            # discard it rather than treating it as a full record.
            trozo = f.read().decode("utf-8", "replace")
    except OSError:
        return None

    lineas = trozo.split("\n")
    if len(lineas) > 1 and trozo and not trozo.startswith("{"):
        lineas = lineas[1:]

    for linea in reversed(lineas):
        if '"rate_limits"' not in linea:
            continue
        try:
            reg = json.loads(linea)
        except ValueError:
            continue
        info = ((reg.get("payload") or {}).get("rate_limits"))
        if isinstance(info, dict):
            return info, epoca(reg.get("timestamp"))
    return None


def codex_window_name(minutes):
    if minutes == 10080:
        return "Weekly"
    if minutes >= 1440:
        return "%d days" % round(minutes / 1440)
    if minutes >= 60:
        return "%d hours" % round(minutes / 60)
    return "%d min" % minutes


def ventana(datos, ident):
    """A Codex primary or secondary window in the view's format.

    Its duration supplies the name: Codex says 10080 minutes where people
    think a week. Not every plan exposes both; secondary can be empty.
    """
    if not isinstance(datos, dict):
        return None

    used = datos.get("usedPercent", datos.get("used_percent"))
    pct = percentage(used)
    if pct is None:
        return None
    minutos = datos.get("windowDurationMins", datos.get("window_minutes")) or 0

    return {
        "id": ident,
        "nombre": codex_window_name(minutos),
        "pct": pct,
        "reinicia": datos.get("resetsAt", datos.get("resets_at")),
        # Codex does not identify the active window; count the tightest.
        "activo": True,
    }


def read_codex_rollout():
    """The rate_limits Codex saved on its last turn."""
    carpeta = primero(CODEX_SESIONES, os.path.isdir)
    if not carpeta:
        return None

    hallazgo = None
    for ruta in rollouts_recientes(carpeta):
        hallazgo = ultimo_limite(ruta)
        if hallazgo:
            break

    if not hallazgo:
        return {"limites": [], "razon": "No data yet — use Codex once to record its limits"}

    info, cuando = hallazgo
    limites = [v for v in (ventana(info.get("primary"), "primaria"),
                           ventana(info.get("secondary"), "secundaria")) if v]

    plan = info.get("plan_type") or ""
    creditos = info.get("credits") or {}

    agente = {
        "plan": plan.title(),
        "actualizado": cuando,
        "fuente": "cache",
        "limites": limites,
    }
    # Only show credits when present: a perpetual zero takes space and
    # says nothing.
    if creditos.get("unlimited"):
        agente["creditos"] = "unlimited"
    elif creditos.get("has_credits"):
        agente["creditos"] = str(creditos.get("balance") or "")
    if not limites:
        agente.update(status="unavailable",
                       razon="Codex recorded this session without quota windows")
    return agente


def codex_plan(value):
    if not isinstance(value, str):
        return ""
    if value == "prolite":
        return "Pro Lite"
    return value.replace("_", " ").replace("-", " ").title()


def codex_rpc_request(proc, selector, ident, method, params=None):
    message = {"method": method, "id": ident}
    if params is not None:
        message["params"] = params
    proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    deadline = time.monotonic() + CODEX_WAIT
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not selector.select(remaining):
            raise TimeoutError("Codex app-server timed out")
        line = proc.stdout.readline()
        if not line:
            raise OSError("Codex app-server closed")
        response = json.loads(line)
        if response.get("id") != ident:
            continue
        if "error" in response or not isinstance(response.get("result"), dict):
            raise ValueError("Codex app-server request failed")
        return response["result"]


def codex_app_server():
    """Read account and live quotas through Codex's versioned local API."""
    proc = subprocess.Popen(
        ["codex", "app-server", "--listen", "stdio://"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, bufsize=1, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    try:
        codex_rpc_request(proc, selector, 0, "initialize", {"clientInfo": {
            "name": "k4_agents", "title": "k4 Agents", "version": "1.0.0"}})
        proc.stdin.write('{"method":"initialized"}\n')
        proc.stdin.flush()
        account = codex_rpc_request(proc, selector, 1, "account/read", {"refreshToken": False})
        current = account.get("account")
        if not isinstance(current, dict):
            return no_data("auth", "Sign in to Codex with ChatGPT to read subscription quotas")

        identity_text = str(current.get("type", "")) + "\0" + str(current.get("email", ""))
        identity = hashlib.sha256(identity_text.encode()).hexdigest()
        path = ["cache", "agents", "codex-usage"]
        now = time.time()
        cached = config_store.get(path, {})
        if (cached.get("identity") == identity
                and 0 <= now - cached.get("time", 0) < CODEX_CACHE_SECONDS
                and isinstance(cached.get("result"), dict)):
            return cached["result"]

        response = codex_rpc_request(proc, selector, 2, "account/rateLimits/read")
        snapshot = response.get("rateLimits")
        alternatives = response.get("rateLimitsByLimitId") or {}
        if not isinstance(snapshot, dict):
            snapshot = {}
        if not any(ventana(snapshot.get(key), key) for key in ("primary", "secondary")):
            for key in sorted(alternatives):
                candidate = alternatives[key]
                if isinstance(candidate, dict) and any(ventana(candidate.get(window), window)
                                                       for window in ("primary", "secondary")):
                    snapshot = candidate
                    break

        limits = [window for window in
                  (ventana(snapshot.get("primary"), "primaria"),
                   ventana(snapshot.get("secondary"), "secundaria")) if window]
        plan = codex_plan(snapshot.get("planType") or current.get("planType"))
        result = {"plan": plan, "actualizado": now, "fuente": "vivo", "limites": limits}
        credits = snapshot.get("credits") or {}
        if credits.get("unlimited"):
            result["creditos"] = "unlimited"
        elif credits.get("hasCredits"):
            result["creditos"] = str(credits.get("balance") or "")
        if not limits:
            result.update(status="unavailable",
                          razon="Codex is signed in, but OpenAI returned no quota windows")
        else:
            result["status"] = "ok"
        try:
            config_store.put(path, {"identity": identity, "time": now, "result": result})
        except (OSError, ValueError):
            pass
        return result
    finally:
        selector.close()
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def read_codex(online=True):
    """Prefer Codex's live account API and retain local logs for offline use."""
    if online:
        try:
            return codex_app_server()
        except (OSError, ValueError, TypeError, KeyError, TimeoutError):
            pass
    local = read_codex_rollout()
    if local is not None:
        return local
    if online:
        return no_data("error", "Could not query Codex usage or find local quota data")
    return no_data("offline", "Offline — no Codex quota data has been recorded locally")


# ── HTTP coding-plan adapters ─────────────────────────────────────────

def percentage(value):
    """A percentage is always 0–100, never a fraction inferred from its size."""
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
        return max(0.0, min(100.0, number)) if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def timestamp(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return (value / 1000 if value > 100_000_000_000 else value) if math.isfinite(value) else None
    return epoca(value)


def quota(ident, name, pct, reset=None, estimated=False):
    return {"id": ident, "nombre": name, "pct": percentage(pct),
            "reinicia": timestamp(reset), "activo": True, "resetEstimated": estimated}


def no_data(status, reason):
    return {"limites": [], "status": status, "razon": reason}


def opencode_key():
    for name in ("OPENCODE_API_KEY", "ZEN_API_KEY"):
        if os.environ.get(name, "").strip():
            return os.environ[name].strip()
    path = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "opencode/auth.json"
    auth = read_json(path) or {}
    for ident in ("opencode-go", "opencode"):
        entry = auth.get(ident, {})
        if isinstance(entry, dict) and entry.get("type") == "api" and isinstance(entry.get("key"), str):
            if entry["key"].strip():
                return entry["key"].strip()
    return None


def zai_key(region, selected):
    name = "ZAI_API_KEY" if region == "global" else "ZHIPUAI_API_KEY"
    if os.environ.get(name, "").strip():
        return os.environ[name].strip()
    # models.dev uses ZHIPU_API_KEY for both regions. Only adopt that alias
    # when the user's selection makes its destination unambiguous.
    regions = set(selected) & {"zai-coding-plan", "zhipuai-coding-plan"}
    if len(regions) == 1:
        return os.environ.get("ZHIPU_API_KEY", "").strip() or None
    return None


def parse_go(payload):
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        raise ValueError("Missing usage")
    limits = []
    for ident, label in (("rolling", "5 hours"), ("weekly", "Weekly"), ("monthly", "Monthly")):
        row = usage.get(ident)
        if isinstance(row, dict) and percentage(row.get("percent")) is not None:
            limits.append(quota(ident, label, row["percent"], row.get("resetsAt")))
    if not limits:
        raise ValueError("Missing windows")
    return {"plan": "Go", "limites": limits}


def parse_zai(payload):
    if payload.get("success") is False:
        return no_data("unavailable", "No active Coding Plan or quota data available")
    data = payload.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("limits"), list):
        raise ValueError("Missing limits")
    limits = []
    for row in data["limits"]:
        if not isinstance(row, dict):
            continue
        kind = row.get("type")
        if kind not in ("TOKENS_LIMIT", "TIME_LIMIT"):
            continue
        pct = percentage(row.get("percentage"))
        if pct is None:
            used, total = row.get("currentValue"), row.get("usage")
            if (isinstance(used, (int, float)) and isinstance(total, (int, float))
                    and not isinstance(total, bool) and total > 0):
                pct = percentage(100 * used / total)
        if pct is None:
            continue
        # The API describes duration using unit: 1=day, 3=hour, 5=minute,
        # 6=month, 7=week. A rolling window never starts at a clock boundary.
        unit, number = row.get("unit"), row.get("number")
        if kind == "TIME_LIMIT":
            ident, label = "tools-monthly", "Monthly tools"
        elif unit == 7 or (unit == 1 and number == 7):
            ident, label = "weekly", "Weekly"
        else:
            ident, label = "rolling", "5 hours"
        reset = row.get("nextResetTime") or row.get("resetTime")
        limits.append(quota(ident, label, pct, reset, estimated=ident == "rolling"))
    if not limits:
        return no_data("unavailable", "No Coding Plan quota data available")
    plan = data.get("planName") or data.get("packageName") or "Coding Plan"
    return {"plan": plan if isinstance(plan, str) else "Coding Plan", "limites": limits}


def query_http(ident, key, url, parser):
    # Cache identity includes the account and regional URL. Never persist
    # credentials, and never reuse another account's quota after a key change.
    identity = hashlib.sha256((url + "\0" + key).encode()).hexdigest()
    path = ["cache", "agents", ident + "-usage"]
    now = time.time()
    cached = config_store.get(path, {})
    if cached.get("identity") == identity and 0 <= now - cached.get("time", 0) < cached.get("ttl", 60):
        return cached["result"]
    ttl = 60
    try:
        payload = request_json(url, headers={"Authorization": "Bearer " + key})
        result = parser(payload)
        result.update(actualizado=now, fuente="vivo")
        result.setdefault("status", "ok")
    except urllib.error.HTTPError as error:
        error.close()
        if error.code in (401, 403):
            result = no_data("auth", "Check your credentials and active subscription")
            ttl = 300
        elif error.code == 429:
            result = no_data("limited", "Too many requests — waiting before retrying")
            ttl = 300
        else:
            result = no_data("error", "Usage service unavailable")
    except (OSError, ValueError, TypeError, KeyError):
        result = no_data("error", "Could not read usage data — check your connection and retry")
    try:
        config_store.put(path, {"identity": identity, "time": now, "ttl": ttl, "result": result})
    except (OSError, ValueError):
        pass
    return result


def read_go(online, selected):
    if not online:
        return no_data("offline", "Offline — live usage is unavailable")
    key = opencode_key()
    if not key:
        return no_data("missing", "Connect OpenCode Go or set OPENCODE_API_KEY")
    return query_http("opencode-go", key, "https://opencode.ai/zen/go/v1/usage", parse_go)


def read_zai(ident, online, selected):
    if not online:
        return no_data("offline", "Offline — live usage is unavailable")
    global_region = ident == "zai-coding-plan"
    key = zai_key("global" if global_region else "china", selected)
    if not key:
        variable = "ZAI_API_KEY" if global_region else "ZHIPUAI_API_KEY"
        return no_data("missing", "Set " + variable + " for this region; restart the bar after exporting it")
    host = "api.z.ai" if global_region else "open.bigmodel.cn"
    return query_http(ident, key, "https://" + host + "/api/monitor/usage/quota/limit", parse_zai)


# ── Registry: catalog identity, tracking scope, detection and query ─────

DEFAULT_PROVIDERS = ("claude", "codex")
PROVIDERS = {
    "claude": {
        "name": "Claude Code", "catalog": "anthropic",
        "scope": "Claude Code subscription quotas",
        "setup": "Sign in to Claude Code and use it once. Reads its OAuth credentials and usage cache; ANTHROPIC_API_KEY does not provide these subscription quotas.",
        "reader": lambda online, selected: lee_claude(online), "binary": "claude",
    },
    "codex": {
        "name": "OpenAI Codex", "catalog": "openai", "scope": "Codex subscription quotas",
        "setup": "Sign in to Codex with ChatGPT. Live checks use Codex's account API; offline checks read local session logs, including CODEX_HOME. OPENAI_API_KEY does not supply these subscription quotas.",
        "reader": lambda online, selected: read_codex(online), "binary": "codex",
    },
    "zai-coding-plan": {
        "name": "Z.AI Coding Plan", "catalog": "zai-coding-plan", "scope": "Global Coding Plan quotas",
        "setup": "Set ZAI_API_KEY in the bar's environment, then restart the bar. ZHIPU_API_KEY is also accepted when only this region is enabled. Keys stay on api.z.ai.",
        "reader": lambda online, selected: read_zai("zai-coding-plan", online, selected),
    },
    "zhipuai-coding-plan": {
        "name": "Zhipu AI Coding Plan", "catalog": "zhipuai-coding-plan", "scope": "China Coding Plan quotas",
        "setup": "Set ZHIPUAI_API_KEY in the bar's environment, then restart the bar. ZHIPU_API_KEY is also accepted when only this region is enabled. Keys stay on open.bigmodel.cn.",
        "reader": lambda online, selected: read_zai("zhipuai-coding-plan", online, selected),
    },
    "opencode-go": {
        "name": "OpenCode Go", "catalog": "opencode-go", "scope": "Go subscription quotas",
        "setup": "Connect OpenCode Go with /connect, or set OPENCODE_API_KEY (ZEN_API_KEY is an alias). Uses the opencode-go auth.json entry, then opencode/Zen as a fallback. One Go usage card; Zen credits are separate.",
        "reader": read_go,
    },
}


def provider_catalog(snapshot=None, refresh=False, online=True, logo=None):
    catalog = load_catalog(snapshot, refresh=refresh and online, logo=logo if online else None)
    by_catalog = {value["catalog"]: (key, value) for key, value in PROVIDERS.items()}
    for row in catalog["providers"]:
        match = by_catalog.get(row["id"])
        row.update(adapter=match[0] if match else "", scope=match[1]["scope"] if match else "",
                   setup=match[1]["setup"] if match else "Usage tracking is not supported yet.")
        if row["id"] == "opencode":
            row["setup"] = "Go subscription usage is available under OpenCode Go. Its adapter can also use your saved Zen key; Zen credit tracking is not supported."
    return catalog


def mira(con_red=True, providers=DEFAULT_PROVIDERS):
    """Only selected providers are discovered; one failure cannot hide others."""
    selected = tuple(dict.fromkeys(providers))
    if any(ident not in PROVIDERS for ident in selected):
        raise ValueError("Unknown provider")
    output = []
    for ident in selected:
        provider = PROVIDERS[ident]
        try:
            if provider.get("binary") and not shutil.which(provider["binary"]):
                result = no_data("missing", "Install and sign in to " + provider["name"])
            else:
                result = provider["reader"](con_red, selected)
            if result is None:
                result = no_data("missing", provider["setup"])
            result.setdefault("status", "ok" if result.get("limites") else "unavailable")
        except Exception:  # Provider isolation; exception text may contain secrets.
            result = no_data("error", "Could not read usage data")
        output.append(dict(result, id=ident, nombre=provider["name"]))
    return {"agentes": output}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--providers", default=",".join(DEFAULT_PROVIDERS), help="Comma-separated usage adapter IDs; empty disables all")
    parser.add_argument("--offline", "--sin-red", action="store_true", dest="offline")
    parser.add_argument("--catalog", action="store_true", help="Read public provider metadata without credential discovery")
    parser.add_argument("--refresh-catalog", action="store_true")
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--logo", help="Cache the selected provider logo with catalog metadata")
    args = parser.parse_args(argv)
    selected = [part.strip() for part in args.providers.split(",") if part.strip()]
    unknown = set(selected) - PROVIDERS.keys()
    if unknown:
        parser.error("Unknown providers: " + ", ".join(sorted(unknown)))
    data = provider_catalog(args.snapshot, args.refresh_catalog, not args.offline, args.logo) if args.catalog else mira(not args.offline, selected)
    json.dump(data, sys.stdout, ensure_ascii=False, allow_nan=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
