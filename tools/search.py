#!/usr/bin/env python3
"""File search for the island module.

Use `fd`: on the tested machine, `plocate` indexed no home paths and its
periodic snapshots missed newly saved files. `fd` scanned 187,000 home files
in 50 ms and searched the current filesystem.

`--hidden` and `--no-ignore` are essential: otherwise fd skips hidden and
gitignored files, including ~/.config. The same search returned no results
without these flags.

    search.py <consulta> [--ambito home|sistema] [--tope N] [--solo dir|archivo]

Emit sorted JSON results with paths, names, sizes, dates and match scores.
"""

import json
import os
import subprocess
import sys
import time

TOPE = 60
# Exclude caches and dependency trees that would overwhelm useful results.
EXCLUIR = [
    "node_modules", ".git", ".cache", "__pycache__", ".venv", "venv",
    ".npm", ".cargo/registry", ".rustup", ".local/share/Trash",
    ".mozilla/firefox/*/cache2", ".steam", "Steam/steamapps",
]

CARPETAS_SISTEMA = ["/usr", "/etc", "/opt", "/srv", "/var/log"]


def ejecutar(consulta, ambito, tope, solo, extensiones):
    orden = ["fd", "--hidden", "--no-ignore", "--absolute-path",
             "--max-results", str(tope * 4), "--ignore-case"]

    for patron in EXCLUIR:
        orden += ["--exclude", patron]

    if solo == "dir":
        orden += ["--type", "directory"]
    elif solo == "archivo":
        orden += ["--type", "file"]

    #  Let fd filter extensions before applying --max-results. Filtering here
    #  would spend the result budget on files that are later discarded.
    for ext in extensiones:
        orden += ["--extension", ext]

    orden.append(consulta)

    if ambito == "sistema":
        orden += CARPETAS_SISTEMA
    else:
        orden.append(os.path.expanduser("~"))

    try:
        r = subprocess.run(orden, capture_output=True, text=True, timeout=8)
    except Exception:
        return []
    return [l for l in r.stdout.split("\n") if l.strip()]


def puntuar(ruta, consulta):
    """Rank better matches first.

    Match the filename rather than its parent directories. Slightly penalize
    deep paths, which tend to contain buried files.
    """
    nombre = os.path.basename(ruta).lower()
    q = consulta.lower()
    if not q:
        return 0

    if nombre == q:
        base = 1000
    elif os.path.splitext(nombre)[0] == q:
        base = 900
    elif nombre.startswith(q):
        base = 700
    elif q in nombre:
        base = 500
    else:
        base = 200                      # matched only the path

    return base - min(200, ruta.count("/") * 8)


def describir(ruta, consulta):
    try:
        st = os.lstat(ruta)
    except OSError:
        return None

    carpeta = os.path.isdir(ruta)
    return {
        "ruta": ruta,
        "nombre": os.path.basename(ruta) or ruta,
        "carpeta": os.path.dirname(ruta),
        "esCarpeta": carpeta,
        "extension": "" if carpeta else os.path.splitext(ruta)[1].lstrip(".").lower(),
        "bytes": 0 if carpeta else st.st_size,
        "cuando": st.st_mtime,
        "punto": puntuar(ruta, consulta),
    }


AYUDA = """Search files by name and return JSON.

    tools/search.py <texto>              search your home directory
    tools/search.py <texto> --ambito /   search scope (home unless sistema)
    tools/search.py <texto> --tope 30    maximum results to return
    tools/search.py <texto> --solo dir   directories (dir) or files (archivo)
    tools/search.py <texto> --ext png,jpg

Queries shorter than two characters return an empty list: the bar calls this
on every keystroke, and a one-character query would scan the entire home.
"""


def main():
    args = sys.argv[1:]
    #  Unknown arguments become query text below. Handle help first so --help
    #  does not become a fruitless search for the literal flag.
    if args and args[0] in ("-h", "--help", "--ayuda"):
        print(AYUDA)
        return

    consulta = ""
    ambito = "home"
    tope = TOPE
    solo = ""
    extensiones = []

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--ambito" and i + 1 < len(args):
            ambito = args[i + 1]; i += 2
        elif a == "--tope" and i + 1 < len(args):
            tope = int(args[i + 1]); i += 2
        elif a == "--solo" and i + 1 < len(args):
            solo = args[i + 1]; i += 2
        elif a == "--ext" and i + 1 < len(args):
            extensiones = [e.strip().lstrip(".")
                           for e in args[i + 1].split(",") if e.strip()]
            i += 2
        else:
            consulta = a; i += 1

    if len(consulta.strip()) < 2:
        print(json.dumps({"resultados": [], "consulta": consulta}), flush=True)
        return

    inicio = time.time()
    rutas = ejecutar(consulta, ambito, tope, solo, extensiones)

    salida = []
    for r in rutas:
        # Strip fd's trailing directory slash so basename and scoring work.
        r = r.rstrip("/") or "/"
        d = describir(r, consulta)
        if d:
            salida.append(d)

    # Best matches first, then newest among ties.
    salida.sort(key=lambda d: (-d["punto"], -d["cuando"]))

    print(json.dumps({
        "consulta": consulta,
        "ambito": ambito,
        "ms": round((time.time() - inicio) * 1000),
        "total": len(salida),
        "resultados": salida[:tope],
    }), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
