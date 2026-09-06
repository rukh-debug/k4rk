#!/usr/bin/env python3
"""Top-consumer walker for services/Sistema.qml.

The QML side reads /proc directly for everything instantaneous; what
it cannot do is list directories, and two things need that: finding
the hwmon temperature files and walking /proc/<pid> for the top
consumers. This helper does both, and only while the System view is
open.

Its first line names the temperature files and whether nvidia-smi
exists (starting a binary that is not there logs a warning every
time, so the QML side refuses to even try):

    {"chips": {"cpu": "/sys/class/hwmon/...", "nvme": "/sys/class/hwmon/...", "gpu": true}}

then one JSON line every few seconds with the per-process deltas:

    {"procesos": [{"pid": 1, "nombre": "...", "cpu": 12.3, "ram": 45}]}

A process's CPU percentage is a rhythm — `ps` reports a lifetime
average, which says nothing about a browser open since yesterday — so
each pass is compared against the previous sample. The first pass
arms the delta and publishes nothing.
"""

import json
import os
import shutil
import sys
import time

INTERVALO = 2.0
HILOS = os.cpu_count() or 1
RELOJ = os.sysconf("SC_CLK_TCK")


# ── temperature files ───────────────────────────────────────────────
#
#  Sought by chip name: k10temp is the Ryzen, coretemp the Intel. The
#  board (gigabyte_wmi, nct6…) publishes half a dozen unlabeled probes
#  that say nothing, so they are ignored. Empty string means "not
#  found", and the view keeps its dash.

CHIPS_CPU = ("k10temp", "coretemp", "zenpower", "cpu_thermal")
ETIQUETAS_CPU = ("Tctl", "Tdie", "Package id 0")


def rutas_temperatura():
    cpu = ""
    nvme = ""

    for base in sorted(os.listdir("/sys/class/hwmon")):
        ruta = os.path.join("/sys/class/hwmon", base)
        try:
            with open(os.path.join(ruta, "name")) as f:
                chip = f.read().strip()
        except OSError:
            continue

        for fichero in sorted(os.listdir(ruta)):
            if not fichero.endswith("_input") or not fichero.startswith("temp"):
                continue

            etiqueta = ""
            try:
                with open(os.path.join(ruta, fichero.replace("_input", "_label"))) as f:
                    etiqueta = f.read().strip()
            except OSError:
                pass

            if chip in CHIPS_CPU and (cpu == "" or etiqueta in ETIQUETAS_CPU):
                cpu = os.path.join(ruta, fichero)
            elif chip == "nvme" and nvme == "":
                nvme = os.path.join(ruta, fichero)

    return {"cpu": cpu, "nvme": nvme}


# ── processes ───────────────────────────────────────────────────────

def lee_procesos():
    salida = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                bruto = f.read()
            # the name sits between parentheses and may hold spaces
            cierre = bruto.rfind(")")
            nombre = bruto[bruto.find("(") + 1:cierre]
            campos = bruto[cierre + 2:].split()
            tiempo = int(campos[11]) + int(campos[12])      # utime + stime
            rss = int(campos[21]) * 4096 / 1048576.0        # pages -> MiB
        except (OSError, ValueError, IndexError):
            continue
        salida[pid] = (nombre, tiempo, rss)
    return salida


def top(antes, ahora, dt, cuantos=6):
    lista = []
    for pid, (nombre, tiempo, rss) in ahora.items():
        if pid not in antes:
            continue
        dcpu = (tiempo - antes[pid][1]) / RELOJ / dt * 100
        if dcpu <= 0.1 and rss < 50:
            continue
        lista.append({"pid": int(pid), "nombre": nombre,
                      "cpu": round(min(dcpu, 100 * HILOS), 1), "ram": round(rss)})

    lista.sort(key=lambda p: (-p["cpu"], -p["ram"]))
    return lista[:cuantos]


# ── loop ────────────────────────────────────────────────────────────

def main():
    chips = rutas_temperatura()
    chips["gpu"] = shutil.which("nvidia-smi") is not None
    print(json.dumps({"chips": chips}), flush=True)

    antes = lee_procesos()
    t_previo = time.monotonic()

    while True:
        time.sleep(INTERVALO)
        ahora = lee_procesos()
        t = time.monotonic()
        dt = max(0.001, t - t_previo)

        print(json.dumps({"procesos": top(antes, ahora, dt)}), flush=True)

        antes = ahora
        t_previo = t


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        # whoever reads closing is not a failure: it is the end
        sys.exit(0)
