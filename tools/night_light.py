"""Offline solar scheduling and checked hyprsunset IPC for the native panel."""

import json
import math
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

UTC = timezone.utc
FADE_SECONDS = 15 * 60


def location_values(location):
    lat, lon = float(location["latitude"]), float(location["longitude"])
    if not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180:
        raise ValueError("Invalid city coordinates")
    ZoneInfo(location["timezone"])
    return lat, lon


def solar_schedule(location, now):
    from astral import Observer
    from astral.sun import elevation, sunrise, sunset

    lat, lon = location_values(location)
    observer = Observer(lat, lon)
    events = []
    # Surround UTC midnight and extreme timezones with enough adjacent dates.
    for offset in range(-2, 3):
        day = now.date() + timedelta(days=offset)
        for kind, calculate in (("sunrise", sunrise), ("sunset", sunset)):
            try:
                events.append((calculate(observer, day, UTC).timestamp(), kind))
            except ValueError:
                pass  # Polar day/night: the sun may not cross the horizon.
    events.sort()
    stamp = now.timestamp()
    past = [event for event in events if event[0] <= stamp]
    upcoming = [event for event in events if event[0] > stamp]
    night = past[-1][1] == "sunset" if past else elevation(observer, now, with_refraction=False) < -0.833
    amount = float(night)
    for boundary, kind in events:
        if abs(stamp - boundary) <= FADE_SECONDS / 2:
            progress = (stamp - boundary + FADE_SECONDS / 2) / FADE_SECONDS
            amount = progress if kind == "sunset" else 1 - progress
            break
    return {
        "amount": amount,
        "night": night,
        "nextBoundary": upcoming[0][0] if upcoming else stamp + 86400,
        "nextEvent": upcoming[0][1] if upcoming else "daily review",
        "sunrise": next((t for t, kind in upcoming if kind == "sunrise"), None),
        "sunset": next((t for t, kind in upcoming if kind == "sunset"), None),
        "polar": not events,
    }


def evaluate(settings, now=None):
    now = now or datetime.now(UTC)
    temperature = int(settings.get("temperature", 4000))
    if not 2500 <= temperature <= 6500:
        raise ValueError("Night temperature must be between 2500 and 6500 K")
    mode = settings.get("mode", "manual")
    if mode not in ("manual", "solar"):
        raise ValueError("Unknown night-light schedule")
    state = {"amount": 0.0, "nextBoundary": None, "nextEvent": "", "needsLocation": False}
    if mode == "solar" and settings.get("location"):
        state.update(solar_schedule(settings["location"], now))
    elif mode == "solar":
        state["needsLocation"] = True
    else:
        state["amount"] = 1.0

    override = settings.get("override") or {}
    until = float(override.get("until", 0))
    overridden = mode == "solar" and settings.get("enabled", False) and until > now.timestamp()
    if overridden:
        state["amount"] = 1.0 if override.get("active") else 0.0
    if not settings.get("enabled", False) or state["needsLocation"]:
        state["amount"] = 0.0
    state["overridden"] = bool(overridden)
    state["overrideUntil"] = until if overridden else None
    state["target"] = round((6500 - (6500 - temperature) * state["amount"]) / 10) * 10
    state["identity"] = state["amount"] == 0
    return state


def ipc(*args):
    result = subprocess.run(["hyprctl", "hyprsunset", *map(str, args)],
                            capture_output=True, text=True, timeout=4)
    text = result.stdout.strip()
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or text or "hyprsunset is unavailable")
    return text


def read_backend():
    identity = ipc("identity", "get")
    if identity not in ("true", "false"):
        raise RuntimeError("hyprsunset identity queries are unavailable; use hyprsunset 0.4 or newer")
    return {"active": identity == "false", "temperature": int(ipc("temperature"))}


def reconcile(settings):
    state = evaluate(settings)
    try:
        current = read_backend()
        if state["identity"] and current["active"]:
            reply = ipc("identity")
            if reply != "ok":
                raise RuntimeError(reply)
        elif not state["identity"] and (not current["active"] or current["temperature"] != state["target"]):
            reply = ipc("temperature", state["target"])
            if reply != "ok":
                raise RuntimeError(reply)
        actual = read_backend()
        if actual["active"] != (not state["identity"]) or (actual["active"] and actual["temperature"] != state["target"]):
            raise RuntimeError("hyprsunset did not apply the requested temperature")
        state.update(actual, available=True)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        state.update(available=False, error=str(exc))
    return state


def search(query):
    if len(query.strip()) < 3:
        return {"results": []}
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urlencode({
        "name": query.strip(), "count": 8, "language": "en", "format": "json",
    })
    request = Request(url, headers={"User-Agent": "k4-night-light/1.0"})
    with urlopen(request, timeout=10) as response:
        data = json.load(response)
    results = []
    for city in data.get("results", []):
        if not city.get("timezone"):
            continue
        location_values(city)
        results.append({key: city.get(key, "") for key in (
            "name", "admin1", "country", "latitude", "longitude", "timezone")})
    return {"results": results}


if __name__ == "__main__":
    try:
        action, payload = sys.argv[1:]
        if action == "search":
            result = search(payload)
        elif action == "evaluate":
            result = evaluate(json.loads(payload))
        elif action == "apply":
            result = reconcile(json.loads(payload))
        else:
            raise ValueError("Unknown night-light operation")
        print(json.dumps(result, allow_nan=False))
    except Exception as exc:
        print(json.dumps({"available": False, "error": str(exc)}))
        sys.exit(1)
