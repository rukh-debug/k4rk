#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Put k4's skill where coding agents will find it.

    python3 tools/agent_skill.py            where it is, and whether it's linked
    python3 tools/agent_skill.py --install  link it
    python3 tools/agent_skill.py --remove   unlink it

(`--instalar` and `--quitar` remain accepted aliases for existing callers.)

The skill teaches agents about k4, its plugins, and its scaffolding command
without repeating that context in every session.

Link rather than copy: the skill lives in the repository, so updating k4 also
updates the instructions agents read. A copy would become stale.
"""

from __future__ import annotations

import os
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
HABILIDAD = RAIZ / "agentes" / "skills" / "k4"

#  Skill lookup paths. Install to each destination so agents share the context.
DESTINOS = [
    pathlib.Path.home() / ".claude" / "skills" / "k4",
    pathlib.Path.home() / ".config" / "agents" / "skills" / "k4",
]


def estado(d):
    if d.is_symlink():
        return "linked" if d.resolve() == HABILIDAD else "linked to something ELSE"
    if d.exists():
        return "occupied by something other than a symlink"
    return "not installed"


def mirar():
    print("Skill: %s" % HABILIDAD)
    if not HABILIDAD.is_dir():
        print("  MISSING. Is the checkout incomplete?")
        return 1
    for d in DESTINOS:
        print("  %-46s %s" % (d, estado(d)))
    return 0


def instalar():
    if not HABILIDAD.is_dir():
        print("cannot find %s" % HABILIDAD, file=sys.stderr)
        return 1
    puestas = 0
    for d in DESTINOS:
        if d.is_symlink() and d.resolve() == HABILIDAD:
            print("  already installed: %s" % d)
            continue
        if d.exists() and not d.is_symlink():
            #  A real file or directory may contain a user-written skill.
            #  Leave it in place rather than replacing the user's work.
            print("  occupied, leaving in place: %s" % d)
            continue
        d.parent.mkdir(parents=True, exist_ok=True)
        if d.is_symlink():
            d.unlink()
        d.symlink_to(HABILIDAD)
        print("  installed: %s" % d)
        puestas += 1
    if puestas:
        print("\nNew agent sessions will know about k4 and how to write a plugin.")
    return 0


def quitar():
    for d in DESTINOS:
        if d.is_symlink() and d.resolve() == HABILIDAD:
            d.unlink()
            print("  removed: %s" % d)
        elif d.exists():
            print("  not ours, leaving in place: %s" % d)
    return 0


if __name__ == "__main__":
    #  English flags and their existing aliases.
    sys.argv = [{"--install": "--instalar",
                 "--remove": "--quitar"}.get(a, a) for a in sys.argv]
    if "--instalar" in sys.argv:
        sys.exit(instalar())
    if "--quitar" in sys.argv:
        sys.exit(quitar())
    if "-h" in sys.argv or "--help" in sys.argv or "--ayuda" in sys.argv:
        print(__doc__)
        sys.exit(0)
    sys.exit(mirar())
