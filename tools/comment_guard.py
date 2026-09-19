#!/usr/bin/env python3
"""Comment-sweep guard: the code under the comments must not move.

Usage: tools/comment_guard.py FILE... (or directories)

Checks unstaged changes against the index using a line-based // heuristic.
Directories are scanned for QML files only; explicit files are also accepted.
Blank lines and pure // lines are ignored; sorted code prefixes must match.

Limitations: this is not a parser or proof of unchanged behavior. It does not
understand block comments, Python # comments or docstrings, and // inside a
string cuts the line early. Sorting can hide reordered code. Staged changes
and untracked file contents are not checked by git diff. Review the diff too.
"""

import pathlib
import re
import subprocess
import sys


def prefijo(linea: str) -> str:
    """The code part of a line: everything before its `//`, if any."""
    #  A `//` inside a string cuts early and can hide a changed suffix.
    corte = linea.find("//")
    return linea if corte < 0 else linea[:corte]


def revisar(ruta: pathlib.Path) -> bool:
    diff = subprocess.run(
        ["git", "diff", "-U0", "--", str(ruta)],
        capture_output=True, text=True).stdout
    quitados, puestos = [], []
    for linea in diff.split("\n"):
        if not linea.startswith(("+", "-")) or linea.startswith(("+++", "---")):
            continue
        cuerpo = linea[1:]
        if not cuerpo.strip():
            continue
        (quitados if linea[0] == "-" else puestos).append(cuerpo)
    bien = True
    #  Ignore pure // lines. Compare sorted prefixes before //; this cannot
    #  distinguish a comment marker from one inside a string or detect reorderings.
    def prefijo(linea):
        corte = linea.find("//")
        return (linea if corte < 0 else linea[:corte]).rstrip()
    quitar_comentarios = lambda ls: [p for p in (prefijo(l) for l in ls) if p]
    if sorted(quitar_comentarios(quitados)) != sorted(quitar_comentarios(puestos)):
        for l in quitados + puestos:
            if prefijo(l):
                print(f"{ruta}: code changed: {'-' if l in quitados else '+'}{l[:100]}")
        bien = False
    return bien


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    fallos = 0
    for arg in sys.argv[1:]:
        ruta = pathlib.Path(arg)
        ficheros = (
            sorted(ruta.rglob("*.qml")) if ruta.is_dir()
            else ([ruta] if ruta.is_file() else []))
        for f in ficheros:
            if not revisar(f):
                fallos += 1
    if fallos:
        return 1
    print("comment sweep heuristic passed; review its documented limitations")
    return 0


if __name__ == "__main__":
    sys.exit(main())
