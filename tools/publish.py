#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Review a plugin submission and, if approved, publish it in the registry.

    python3 tools/publish.py --revisar <cuerpo.txt>   report in Markdown
    python3 tools/publish.py --anadir  <cuerpo.txt>   add the registry entry

The submission arrives as an issue form. This script reads its body, fetches
THE SPECIFIED COMMIT, validates it with the same `tools/plugins.py` used
everywhere else, and writes a report.

Two deliberate limits:

**It never executes plugin code.** It clones, reads files, and compares what
the manifest DECLARES against what the QML actually uses. This is static
analysis only. Running a stranger's code on the runner to decide whether it
is trustworthy would defeat the purpose.

**It never publishes automatically.** `--revisar` runs whenever the issue is
opened or edited and leaves the registry alone; `--anadir` is triggered only
by a label applied by a person. The bot reports findings; publication needs
human approval.

The report is tied to the commit: if the reviewed and approved SHAs differ,
`--anadir` refuses. Otherwise approval would cover whatever that repository
contains in the future, a promise nobody can make.
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import re
import subprocess
import sys

from plugins import normalizar

RAIZ = pathlib.Path(__file__).resolve().parent.parent
REGISTRO = RAIZ / "plugins" / "registro.json"
GUION = RAIZ / "tools" / "plugins.py"

RE_SHA = re.compile(r"^[0-9a-f]{40}$")
RE_REPO = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$")


#  ── read the form ───────────────────────────────────────────────────
#
#  GitHub issue forms arrive as Markdown: `### ` followed by the field label,
#  with its value underneath. We parse this rather than JSON because the API
#  does not return the fields separately.

def campos(cuerpo):
    """Return form fields keyed by lowercase labels."""
    fuera = {}
    rotulo = None
    lineas = []
    for linea in (cuerpo or "").splitlines():
        if linea.startswith("### "):
            if rotulo:
                fuera[rotulo] = "\n".join(lineas).strip()
            rotulo = linea[4:].strip().lower()
            lineas = []
        elif rotulo:
            lineas.append(linea)
    if rotulo:
        fuera[rotulo] = "\n".join(lineas).strip()
    #  GitHub writes "_No response_" for an empty optional field.
    return {k: ("" if v == "_No response_" else v) for k, v in fuera.items()}


def envio(cuerpo):
    """Return cleaned submission fields and any validation errors."""
    c = campos(cuerpo)

    def dame(*nombres):
        for n in nombres:
            if c.get(n):
                return c[n].strip()
        return ""

    d = {
        "repo": dame("repositorio", "repository", "repo"),
        "commit": dame("commit", "sha").lower(),
        "carpeta": dame("carpeta", "folder", "subcarpeta"),
    }
    malos = []
    if not RE_REPO.match(d["repo"]):
        malos.append("The repository must be a public GitHub URL, "
                     "in the form `https://github.com/owner/repo`.")
    if not RE_SHA.match(d["commit"]):
        malos.append("The commit must be the full 40-character lowercase SHA. "
                     "A branch is not enough: it can move after review, so "
                     "the installed code would no longer be the reviewed code.")
    if d["carpeta"] and (d["carpeta"].startswith("/")
                         or ".." in d["carpeta"].split("/")):
        malos.append("The folder must be relative and contain no `..`.")
    d["repo"] = d["repo"].rstrip("/")
    return d, malos


#  ── examine the plugin ───────────────────────────────────────────────

def examinar(d):
    """Return the `plugins.py --examine` result for that exact commit."""
    orden = [sys.executable, str(GUION), "--examine", d["repo"],
             "--json", "--commit", d["commit"]]
    if d["carpeta"]:
        orden += ["--folder", d["carpeta"]]
    try:
        p = subprocess.run(orden, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return {"ok": False, "motivo": "the repository took too long to clone "
                                       "(more than ten minutes)"}
    for linea in reversed((p.stdout or "").strip().splitlines()):
        linea = linea.strip()
        if linea.startswith("{"):
            try:
                return json.loads(linea)
            except ValueError:
                continue
    return {"ok": False,
            "motivo": (p.stderr or "").strip()[:400] or "no response"}


def ya_publicado(ident):
    try:
        d = json.loads(REGISTRO.read_text())
    except Exception:
        return None
    for e in d.get("plugins") or []:
        if str(e.get("id")) == ident:
            return e
    return None


#  ── the report ───────────────────────────────────────────────────────

def informe(d, malos, res):
    """Return Markdown for the issue comment and the verdict."""
    if malos:
        cuerpo = ["The form needs some corrections:", ""]
        cuerpo += ["- " + m for m in malos]
        cuerpo += ["", "Edit the issue to trigger another automatic review."]
        return "\n".join(cuerpo), "necesita-arreglos"

    if not res.get("ok"):
        return ("Could not validate that commit:\n\n> %s\n\n"
                "Fix it and edit the issue to trigger another automatic review."
                % res.get("motivo", "no reason given"), "necesita-arreglos")

    p = normalizar(res["plugin"])
    ident = str(p.get("id", ""))
    antes = ya_publicado(ident)
    permisos = p.get("permissions") or []
    superficies = p.get("surfaces") or []

    l = []
    l.append("**%s** · `%s` · v%s" % (p.get("title", ident), ident,
                                      p.get("version", "0")))
    if p.get("description"):
        l.append("")
        l.append(p["description"])
    l.append("")
    l.append("| | |")
    l.append("|---|---|")
    l.append("| Repository | %s |" % d["repo"])
    l.append("| Commit | `%s` |" % d["commit"])
    if d["carpeta"]:
        l.append("| Folder | `%s` |" % d["carpeta"])
    l.append("| Required host | `%s` |" % (p.get("host") or "any"))
    l.append("| Permissions | %s |"
             % (", ".join("`%s`" % x for x in permisos) if permisos
                 else "none"))
    l.append("| Surfaces | %s |"
             % (", ".join("`%s`" % x for x in superficies) if superficies
                 else "undeclared"))
    l.append("")

    if antes:
        if str(antes.get("commit") or "") == d["commit"]:
            l.append("That id is already published **at this same commit**: "
                     "there is nothing to change.")
            return "\n".join(l), "necesita-arreglos"
        l.append("Updates `%s`, which is already published at `%s`."
                 % (ident, str(antes.get("commit") or "?")[:12]))
        l.append("")

    #  Report matching rules with explanations and fixes. A warning without
    #  an actionable fix gets ignored and serves no purpose.
    reglas = res.get("reglas") or []
    bloquean = [r for r in reglas if r.get("bloquea")]
    if reglas:
        l.append("")
        l.append("### Findings")
        l.append("")
        for r in reglas:
            l.append("**%s** — %s  \n`%s`"
                     % ("Must be fixed" if r.get("bloquea") else "Needs review",
                        r.get("que", r.get("id")), r.get("donde", "")))
            l.append("")
            l.append("> %s" % r.get("porque", ""))
            l.append("")
            for paso in r.get("arreglo") or []:
                l.append("- %s" % paso)
            l.append("")

    l.append("Validated with `tools/plugins.py`, which compares what the "
             "manifest declares against what the QML actually uses: "
             "undeclared usage prevents loading, so such a plugin would "
             "not reach this stage.")
    l.append("")
    l.append("**This is not a security audit.** It is a static check of a "
             "specific commit, without executing any plugin code. A plugin "
             "runs inside the bar and can do anything the bar can do; "
             "permissions describe what it declares, not a sandbox.")

    #  Requesting permissions is normal — a player needs sound — but a person
    #  must review them before approving publication.
    if bloquean:
        l.append("")
        l.append("The findings above must be fixed before publication: they"
                 " can make the code people run differ from this commit,"
                 " defeating the review. Push the fix and edit the issue"
                 " with the new SHA.")
        return "\n".join(l), "necesita-arreglos"

    etiqueta = ("revision-de-seguridad" if (permisos or reglas) else "validado")
    if permisos or reglas:
        l.append("")
        l.append("None of this blocks publication, but a person must review it"
                 " before approval.")
    return "\n".join(l), etiqueta


#  ── publish ──────────────────────────────────────────────────────────

def anadir(d, res):
    """Add the registry entry, only after a person applies the approval label."""
    if not res.get("ok"):
        print("invalid: publication refused", file=sys.stderr)
        return 1
    #  The report is tied to a commit; stop if a different one is approved.
    #  Approving a repository would approve whatever it contains later.
    if res.get("commit") != d["commit"]:
        print("the reviewed commit (%s) differs from the approved commit (%s)"
              % (res.get("commit"), d["commit"]), file=sys.stderr)
        return 1
    #  Even an approval label cannot override a blocking finding: human
    #  judgment resolves ambiguity, not unequivocal violations.
    bloquean = [r for r in (res.get("reglas") or []) if r.get("bloquea")]
    if bloquean:
        print("publication refused, %d blocking finding(s): %s"
              % (len(bloquean), ", ".join(r["id"] for r in bloquean)),
              file=sys.stderr)
        return 1

    p = res["plugin"]
    ident = str(p.get("id", ""))
    datos = json.loads(REGISTRO.read_text())
    entradas = datos.setdefault("plugins", [])
    nueva = {
        "id": ident,
        "title": p.get("title", ident),
        "description": p.get("description", ""),
        "repo": d["repo"],
        "commit": d["commit"],
    }
    if d["carpeta"]:
        nueva["carpeta"] = d["carpeta"]

    for i, e in enumerate(entradas):
        if str(e.get("id")) == ident:
            #  Preserve registry metadata absent from the submission, such as
            #  the author: a version update should not erase it.
            nueva = {**e, **nueva}
            entradas[i] = nueva
            break
    else:
        entradas.append(nueva)

    REGISTRO.write_text(json.dumps(datos, ensure_ascii=False, indent=1) + "\n")
    print("published: %s at %s" % (ident, d["commit"][:12]))
    return 0


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "--ayuda"):
        print(__doc__)
        return 0
    orden = args[0]
    if len(args) < 2:
        print("missing the file containing the issue body",
              file=sys.stderr)
        return 2
    cuerpo = io.open(args[1], encoding="utf-8").read()
    d, malos = envio(cuerpo)
    res = examinar(d) if not malos else {"ok": False, "motivo": "formulario"}

    if orden == "--revisar":
        texto, etiqueta = informe(d, malos, res)
        print(texto)
        #  Write the label to GitHub's output file, not stdout: stdout holds
        #  the report and is posted verbatim as a comment.
        salidas = os.environ.get("GITHUB_OUTPUT")
        if salidas:
            with io.open(salidas, "a", encoding="utf-8") as f:
                f.write("etiqueta=%s\n" % etiqueta)
                f.write("commit=%s\n" % d["commit"])
                f.write("id=%s\n" % (res.get("plugin", {}).get("id", "")
                                     if res.get("ok") else ""))
        return 0
    if orden == "--anadir":
        if malos:
            print("invalid form: publication refused", file=sys.stderr)
            return 1
        return anadir(d, res)
    print("unknown command %r" % orden, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
