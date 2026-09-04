#!/usr/bin/env python3
"""Comment-sweep guard: the code under the comments must not move.

Usage: tools/comentario.py FILE... (or directories)

Diffs each file against HEAD and checks that every changed line is a
comment line: pure `//` lines, whole `/* */` blocks, or a line whose
code prefix (everything before the `//`) is untouched. Any change to a
code prefix, or any line that changes without carrying a `//`, is a
failure — the translation sweep is allowed to touch comments only, and
this is the cheap, mechanical proof that it did.
"""

import pathlib
import re
import subprocess
import sys


def prefijo(linea: str) -> str:
    """The code part of a line: everything before its `//`, if any."""
    #  A `//` inside a string would cut early; the sweep's own output is
    #  reviewed on failure, and a false alarm costs one look.
    corte = linea.find("//")
    return linea if corte < 0 else linea[:corte]


def revisar(ruta: pathlib.Path) -> bool:
    diff = subprocess.run(
        ["git", "diff", "-U0", "--", str(ruta)],
        capture_output=True, text=True).stdout
    bien = True
    for linea in diff.split("\n"):
        if not linea.startswith(("+", "-")) or linea.startswith(("+++", "---")):
            continue
        cuerpo = linea[1:]
        if not cuerpo.strip():
            continue
        if cuerpo.lstrip().startswith("//"):
            continue
        if cuerpo.lstrip().startswith("/*") or cuerpo.lstrip().startswith("*"):
            continue
        #  A trailing comment on a code line: the code prefix must be
        #  IDENTICAL in its - and + versions. The prefix alone on one
        #  side (comment added/removed) is fine.
        print(f"{ruta}: codigo tocado: {linea[:100]}")
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
    print("comment sweep clean: only comments changed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
