#!/usr/bin/env python3
"""On-demand hardware discovery and interval process telemetry for k4.

The QML hot path reads procfs directly. This helper handles directory walks,
GPU providers and filesystem capacity only while the detailed monitor is open.
All sizes are bytes at the boundary; process RSS is MiB for the existing model.
"""

import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

INTERVALO = 2.0
RELOJ = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")


def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeError):
        return default


def number(path):
    try:
        return int(read(path))
    except ValueError:
        return None


def rutas_temperatura(root=Path("/sys/class/hwmon")):
    candidates = []
    nvme = ""
    for base in sorted(root.glob("hwmon*")):
        chip = read(base / "name")
        for sensor in sorted(base.glob("temp*_input")):
            label = read(sensor.with_name(sensor.name.replace("_input", "_label")))
            if chip in ("k10temp", "coretemp", "zenpower", "cpu_thermal"):
                priority = {"Tdie": 0, "Package id 0": 1, "Tctl": 2}.get(label, 3)
                candidates.append((priority, str(sensor)))
            elif chip == "nvme" and not nvme:
                nvme = str(sensor)
    return {"cpu": min(candidates)[1] if candidates else "", "nvme": nvme}


def discover_gpu(root=Path("/sys/class/drm")):
    # Prefer a readable kernel counter; do not infer zero from unsupported hardware.
    cards = sorted(p for p in root.glob("card*") if p.name[4:].isdigit())
    for card in cards:
        device = card / "device"
        if (device / "gpu_busy_percent").exists():
            name = read(device / "product_name") or "AMD graphics"
            return {"provider": "sysfs", "path": str(device), "name": name}
    if shutil.which("nvidia-smi"):
        return {"provider": "nvidia", "name": "NVIDIA graphics"}
    return None


def gpu_reading(device):
    if not device:
        return None
    if device["provider"] == "sysfs":
        path = Path(device["path"])
        temp = None
        for hwmon in sorted((path / "hwmon").glob("hwmon*")):
            raw = number(hwmon / "temp1_input")
            if raw is not None:
                temp = raw / 1000
                break
        return {"name": device["name"], "usage": number(path / "gpu_busy_percent"),
                "temperature": temp, "used": number(path / "mem_info_vram_used"),
                "total": number(path / "mem_info_vram_total"),
                "memoryLabel": "VRAM / reserved graphics memory"}
    try:
        result = subprocess.run([
            "nvidia-smi", "--id=0",
            "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total",
            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=1.5)
        if result.returncode:
            return None
        fields = result.stdout.strip().splitlines()[0].split(",")
        def value(index, scale=1):
            try:
                value = float(fields[index].strip()) * scale
                return value if math.isfinite(value) else None
            except (ValueError, IndexError):
                return None
        return {"name": fields[0].strip(), "usage": value(1), "temperature": value(2),
                "used": value(3, 1048576), "total": value(4, 1048576), "memoryLabel": "VRAM"}
    except (OSError, subprocess.TimeoutExpired, IndexError):
        return None


def storage(path=None):
    path = path or str(Path.home())
    try:
        data = os.statvfs(path)
        total = data.f_blocks * data.f_frsize
        used = (data.f_blocks - data.f_bfree) * data.f_frsize
        available = data.f_bavail * data.f_frsize
        # Like df, use the space accessible to this user as the denominator.
        percent = used / (used + available) * 100 if used + available else 0
        identity = filesystem_identity(path)
        return dict(identity, path=path, total=total, used=used, available=available,
                    reserved=max(0, total - used - available), percent=percent)
    except OSError:
        return None


def filesystem_identity(path, mountinfo=None):
    path = os.path.realpath(path)
    matches = []
    for line in (mountinfo if mountinfo is not None else read("/proc/self/mountinfo")).splitlines():
        parts = line.split(" - ")
        if len(parts) != 2:
            continue
        left, right = parts[0].split(), parts[1].split()
        if len(left) < 5 or len(right) < 2:
            continue
        mount = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), left[4])
        if path == mount or path.startswith(mount.rstrip("/") + "/"):
            matches.append({"mount": mount, "filesystem": right[0], "device": right[1]})
    return max(matches, key=lambda m: len(m["mount"])) if matches else {"mount": path, "filesystem": "", "device": ""}


def metadata():
    cpu_name = next((line.split(":", 1)[1].strip() for line in read("/proc/cpuinfo").splitlines()
                     if line.startswith("model name")), "Processor")
    return {"chips": rutas_temperatura(), "cpuName": cpu_name, "gpu": discover_gpu()}


def parse_process(raw):
    end = raw.rfind(")")
    fields = raw[end + 2:].split()
    return (raw[raw.find("(") + 1:end], int(fields[11]) + int(fields[12]),
            max(0, int(fields[21])) * PAGE_SIZE / 1048576, int(fields[19]))


def lee_procesos():
    result = {}
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                result[entry.name] = parse_process((entry / "stat").read_text())
            except (OSError, ValueError, IndexError):
                pass
    return result


def top(before, current, dt, cuantos=80):
    if dt <= 0 or dt > 10:
        return []
    rows = []
    for pid, (name, ticks, rss, start) in current.items():
        previous = before.get(pid)
        if not previous or start != previous[3] or ticks < previous[1]:
            continue
        cpu = (ticks - previous[1]) / RELOJ / dt * 100
        rows.append({"pid": int(pid), "nombre": name, "cpu": round(cpu, 1),
                     "ram": round(rss, 1), "start": str(start)})
    # Preserve top memory consumers as well as CPU consumers for either sort order.
    by_cpu = sorted(rows, key=lambda p: (-p["cpu"], -p["ram"], p["pid"]))[:cuantos]
    by_ram = sorted(rows, key=lambda p: (-p["ram"], -p["cpu"], p["pid"]))[:cuantos]
    return list({p["pid"]: p for p in by_cpu + by_ram}.values())


def terminate(pid, start):
    # Bind the signal to the process identity, including PID reuse during the action.
    fd = os.pidfd_open(pid)
    try:
        current = parse_process(Path(f"/proc/{pid}/stat").read_text())
        if str(current[3]) != start:
            raise ProcessLookupError("The process has already exited")
        signal.pidfd_send_signal(fd, signal.SIGTERM)
    finally:
        os.close(fd)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--terminate":
        try:
            terminate(int(sys.argv[2]), sys.argv[3])
            print("Termination requested")
        except (OSError, ValueError) as error:
            print(f"Unable to end process: {error}")
        return
    info = metadata()
    print(json.dumps(info), flush=True)
    if "--discover" in sys.argv:
        return
    before = lee_procesos()
    previous_time = time.monotonic()
    last_storage = 0
    while True:
        now = time.monotonic()
        payload = {"sampleTime": time.clock_gettime(time.CLOCK_BOOTTIME), "gpuReading": gpu_reading(info["gpu"])}
        if now - last_storage >= 30:
            payload["storage"] = storage()
            last_storage = now
        current = lee_procesos()
        sample_time = time.monotonic()
        if sample_time - previous_time >= 0.5:
            payload["procesos"] = top(before, current, sample_time - previous_time)
            before, previous_time = current, sample_time
        print(json.dumps(payload), flush=True)
        time.sleep(max(0.1, INTERVALO - (time.monotonic() - now)))


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
