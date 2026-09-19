#!/usr/bin/env python3
"""Check documentation claims against the code.

    python3 tools/docs_check.py

`tools/api.py` checks that API types are mentioned. A mention alone does not
make the description accurate: renamed members, removed permissions and stale
IPC commands can leave a guide unusable.

This checks mechanically recognizable claims:

  · documented `K4.Tipo.miembro` references against api/K4/Tipo.qml;
  · permission and rule tables against tools/plugins.py;
  · cited IPC commands for known targets against their handlers;
  · cited `tools/X.py --opcion` flags against script string literals;
  · cited repository paths against files on disk;
  · eligible complete QML examples with qmllint, when available;
  · recognized numeric claims against source constants;
  · cited shortcuts against hypr/k4.lua.

This does NOT establish that prose accurately describes behavior. An example
that passes lint can still be explained incorrectly. That requires review.
"""
from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
API = RAIZ / "api" / "K4"

#  Documents that describe the API and can contain stale claims about it.
DOCUMENTOS = ["docs/PLUGINS.md", "docs/API.md", "api/README.md", "README.md"]

#  Deliberately invented example paths. Text alone cannot distinguish a stale
#  path from a file the reader is meant to create. Keep this list small enough
#  to review at a glance.
INVENTADOS = {
    "services/MyGame.qml", "GameView.qml", "GamePlugin.qml", "Battle.qml",
    "Party.qml", "Achievements.qml", "Inventory.qml",
}

#  Inherited Qt members: documenting these is not an error.
HEREDADOS = {"objectName", "parent", "children", "data", "width", "height",
             "x", "y", "z", "visible", "opacity", "enabled", "anchors",
             "implicitWidth", "implicitHeight", "text", "color", "font",
             "source", "status", "running", "interval", "repeat", "target"}


def miembros_de(tipo):
    """Return properties, functions and signals declared by an API type."""
    f = API / (tipo + ".qml")
    if not f.is_file():
        return None
    texto = "\n".join(re.sub(r"//.*$", "", l) for l in f.read_text().split("\n"))
    salida = set()
    salida |= set(re.findall(r"\bproperty\s+(?:alias\s+)?[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\breadonly\s+property\s+[\w<>.]+\s+(\w+)", texto))
    salida |= set(re.findall(r"\bfunction\s+(\w+)\s*\(", texto))
    salida |= set(re.findall(r"\bsignal\s+(\w+)", texto))
    #  Re-exported types (`IpcHandler {}`, `SoundEffect {}`) inherit members
    #  whose declarations are not available here. Avoid false missing members.
    if re.search(r"^\s*(IconImage|IpcHandler|SoundEffect|GlobalShortcut|"
                 r"QsMenuOpener|LazyLoader|PamContext|WlSessionLock\w*)\s*\{",
                 texto, re.M):
        return None
    return salida


def revisar_miembros(doc, texto):
    fallos = []
    for tipo, miembro in re.findall(r"\bK4\.([A-Z]\w+)\.(\w+)", texto):
        declarados = miembros_de(tipo)
        if declarados is None:          # unknown or re-exported type
            if not (API / (tipo + ".qml")).is_file():
                fallos.append(f"{doc}: K4.{tipo} does not exist")
            continue
        if miembro not in declarados and miembro not in HEREDADOS:
            fallos.append(f"{doc}: K4.{tipo}.{miembro} does not exist "
                          f"(not declared in api/K4/{tipo}.qml)")
    return fallos


def revisar_permisos(doc, texto):
    """Compare documented permissions with those checked by the code."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("p", RAIZ / "tools" / "plugins.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    reales = set(mod.PERMISOS)

    fallos = []
    #  Only the full guide contains the permission table.
    if doc != "docs/PLUGINS.md":
        return fallos

    #  Check the TABLE: a passing mention elsewhere must not conceal a missing
    #  row. Readers look here to discover available permissions.
    #  `[\w-]` includes hyphenated permission names that `\w+` would miss.
    documentados = set(re.findall(r"^\| `([\w-]+)` \|", texto, re.M))

    #  Permissions and named rules use the same table format. Check both.
    reglas = {r["id"] for r in getattr(mod, "REGLAS", [])}

    for p in sorted(reales - documentados):
        fallos.append(f"{doc}: permission `{p}` exists but is missing from the table")
    for r in sorted(reglas - documentados):
        fallos.append(f"{doc}: rule `{r}` exists but is missing from the table")
    #  Conversely, invented permissions lead to rejected manifests, and
    #  invented rules describe warnings that will never be emitted.
    for p in sorted(documentados - reales - reglas):
        fallos.append(f"{doc}: table entry `{p}` is neither a permission nor a rule")
    return fallos


def ordenes_ipc():
    """Return functions published by IpcHandler instances, grouped by target."""
    salida = {}
    #  Examples count: commands such as `k4.hola toggle` must remain usable
    #  when copied from the guide. Native surfaces publish from services/ now.
    for f in (list((RAIZ / "plugins").rglob("*.qml"))
              + list((RAIZ / "services").rglob("*.qml"))
              + list((RAIZ / "ejemplos").rglob("*.qml"))
              + [RAIZ / "shell.qml"]):
        texto = f.read_text()
        for m in re.finditer(r'target:\s*"([\w.]+)"', texto):
            objetivo = m.group(1)
            #  Count braces from the target to the end of the block.
            resto = texto[m.end():]
            nivel, fin = 1, len(resto)
            for i, c in enumerate(resto):
                if c == "{":
                    nivel += 1
                elif c == "}":
                    nivel -= 1
                    if nivel == 0:
                        fin = i
                        break
            salida.setdefault(objetivo, set()).update(
                re.findall(r"\bfunction\s+(\w+)\s*\(", resto[:fin]))
    return salida


def revisar_ipc(doc, texto):
    ordenes = ordenes_ipc()
    fallos = []
    ids = {p.name for p in (RAIZ / "plugins").iterdir() if p.is_dir()}
    for objetivo, orden in re.findall(r"\bcall\s+(k4[\w.]*)\s+(\w+)", texto):
        conocidas = ordenes.get(objetivo)
        if conocidas is None:
            #  Unknown targets are often invented examples ("k4.hello").
            #  Check commands attributed to real targets only.
            continue
        if orden not in conocidas:
            fallos.append(f"{doc}: {objetivo} has no command {orden}")
    return fallos


def revisar_opciones(doc, texto):
    fallos = []
    for guion, opcion in re.findall(r"tools/(\w+\.py)\s+(--[\w-]+)", texto):
        f = RAIZ / "tools" / guion
        if not f.is_file():
            fallos.append(f"{doc}: tools/{guion} does not exist")
        elif f'"{opcion}"' not in f.read_text():
            fallos.append(f"{doc}: tools/{guion} does not recognize {opcion}")
    return fallos


def revisar_rutas(doc, texto):
    """Check repository files and directories cited in backticks."""
    fallos = []
    for cita in set(re.findall(r"`([\w./-]+\.(?:qml|py|json|md|tsv|lua|conf))`",
                               texto)):
        #  Without a slash, names such as "plugin.json" are not repository
        #  paths and cannot be checked for existence here.
        if "/" not in cita or cita.startswith(("~", "/")) or "*" in cita:
            continue
        if cita in INVENTADOS:
            continue
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cites {cita}, which does not exist")
    for cita in set(re.findall(r"`(ejemplos/\w+|plugins/\w+|api/K4|tools)/?`",
                               texto)):
        if not (RAIZ / cita).exists():
            fallos.append(f"{doc}: cites {cita}/, which does not exist")
    return fallos


#  Extract numbers from the guide, then compare with source constants. Matching
#  only the expected number would silently miss a stale claim with a new value.
#  The current guide has no numeric maximum-height claim; recognize the English
#  form if one is reintroduced. These patterns do not validate arbitrary prose.
NUMEROS = [
    (r"\*\*(\d+)×\d+\*\*", "tools/plugins.py", r"ICONO_MINIMO\s*=\s*(\d+)",
     "minimum PNG icon width"),
    (r"\*\*\d+×(\d+)\*\*", "tools/plugins.py", r"ICONO_MINIMO\s*=\s*(\d+)",
     "minimum PNG icon height"),
    (r"less than\s+(\d+)\s+MB", "tools/plugins.py",
     r"ICONO_MAXIMO_MB\s*=\s*(\d+)", "maximum icon size"),
    (r"\((\d+) today\)", "core/Theme.qml", r"maxIslandHeight:\s*(\d+)",
     "maximum island height"),
]


def revisar_numeros(doc, texto):
    fallos = []
    for en_guia, fuente, en_codigo, que in NUMEROS:
        dicho = list(re.finditer(en_guia, texto))
        if not dicho:
            continue
        m = re.search(en_codigo, (RAIZ / fuente).read_text())
        if not m:
            fallos.append(f"{doc}: cannot find {que} in {fuente}")
            continue
        for cita in dicho:
            if cita.group(1) != m.group(1):
                fallos.append(f"{doc}: claims {cita.group(1)} for {que}, but "
                              f"{fuente} uses {m.group(1)}")
    return fallos


def revisar_atajos(doc, texto):
    """Documented shortcuts must exist in hypr/k4.lua."""
    lua = (RAIZ / "hypr" / "k4.lua").read_text()
    fallos = []
    for combo in set(re.findall(r"\bSUPER\+((?:SHIFT\+|ALT\+|CONTROL\+)*\w+)",
                                texto)):
        partes = combo.split("+")
        tecla = partes[-1]
        mods = partes[:-1]
        #  Lua spells this as `mod .. " + SHIFT + Space"`.
        esperado = " + ".join(mods + [tecla])
        if not re.search(r'mod \.\. " \+ %s"' % re.escape(esperado), lua):
            fallos.append(f"{doc}: promises shortcut SUPER+{combo}, but "
                          f"hypr/k4.lua does not bind it")
    return fallos


#  qmllint has exited silently with 255 on typed functions such as
#  `function toggle(): void`. Quickshell IPC requires those annotations;
#  strip return types only from the temporary lint input.
RE_TIPADA = re.compile(r"function (\w+)\(([^)]*)\):\s*\w+")


def revisar_ejemplos(doc, texto):
    """Lint eligible complete QML examples against the real API."""
    if not shutil.which("qmllint"):
        print(f"warning: {doc}: qmllint not found; QML example checks skipped",
              file=sys.stderr)
        return []
    fallos = []
    bloques = re.findall(r"```qml\n(.*?)```", texto, re.S)
    for i, bloque in enumerate(bloques, 1):
        cuerpo = RE_TIPADA.sub(r"function \1(\2)", bloque)
        sin_comentarios = "\n".join(
            l for l in cuerpo.split("\n") if not l.strip().startswith("//"))
        primera = next((l for l in sin_comentarios.split("\n") if l.strip()), "")
        #  Only complete objects: wrapping loose properties invents context.
        if not re.match(r"^[A-Z]\w*(\.\w+)?\s*\{", primera.strip()):
            continue
        #  Ellipses stand for reader-supplied code and cannot be linted.
        if re.search(r"(^|\s)\.\.\.($|\s)", sin_comentarios):
            continue
        #  Side-by-side top-level objects do not form a valid QML file.
        if len(re.findall(r"^[A-Z]\w*(?:\.\w+)?\s*\{", sin_comentarios,
                          re.M)) > 1:
            continue
        if "import " not in cuerpo:
            cuerpo = "import QtQuick\nimport QtQuick.Layouts\nimport K4 as K4\n\n" + cuerpo
        tmp = RAIZ / "tools" / ".guia_tmp.qml"
        tmp.write_text(cuerpo)
        r = subprocess.run(["qmllint", "-I", str(RAIZ / "api"), str(tmp)],
                           capture_output=True, text=True)
        tmp.unlink(missing_ok=True)
        if r.returncode != 0:
            aviso = (r.stdout + r.stderr).strip().split("\n")
            aviso = next((l for l in aviso if l.strip()), "qmllint exited with %d"
                         % r.returncode)
            fallos.append(f"{doc}: example {i} failed lint: {aviso[:120]}")
    return fallos


def revisar_motivos():
    """Every emitted reason code must have a sentence in `Motivos`.

    A code without a sentence does not fail: the raw code shows up in the
    interface — «sin-declarar» in the middle of Settings — which is ugly and
    says nothing to whoever has not read the script. It is exactly the bug
    there was, and the only way to keep it away is to stop the flow when a
    code arrives without its sentence.
    """
    fallos = []
    motivos = RAIZ / "services" / "Motivos.qml"
    if not motivos.is_file():
        return ["missing services/Motivos.qml"]
    bloque = motivos.read_text().split("readonly property var tabla")
    if len(bloque) < 2:
        return ["services/Motivos.qml no longer has the reason table"]
    conocidos = set(re.findall(r'"([^"\n]+)"\s*:\s*"',
                               bloque[1].split("})")[0]))

    #  Reasons emitted by scripts and by the bar itself.
    emitidos = {}
    for ruta in list((RAIZ / "tools").glob("*.py")):
        if ruta.name.startswith("prueba_"):
            continue
        t = ruta.read_text()
        for m in re.finditer(r'motivo=["\']([a-z][a-z0-9-]*)["\']', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)
        for m in re.finditer(r'mal\(\s*"([a-z][a-z0-9-]*)"', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)
    for ruta in list((RAIZ / "services").glob("*.qml")) \
            + list((RAIZ / "plugins").glob("*/*.qml")):
        t = ruta.read_text()
        for m in re.finditer(
                r'(?:fallo|fotoFallida|videoFallido)\(\s*"([a-z][a-z0-9-]*)"', t):
            emitidos.setdefault(m.group(1), set()).add(ruta.name)

    for codigo, donde in sorted(emitidos.items()):
        if codigo not in conocidos:
            fallos.append("services/Motivos.qml: missing text for reason "
                          "`%s`, emitted by %s"
                          % (codigo, ", ".join(sorted(donde))))
    return fallos


def main():
    fallos = []
    for doc in DOCUMENTOS:
        f = RAIZ / doc
        if not f.is_file():
            fallos.append(f"missing document {doc}")
            continue
        texto = f.read_text()
        fallos += revisar_miembros(doc, texto)
        fallos += revisar_permisos(doc, texto)
        fallos += revisar_ipc(doc, texto)
        fallos += revisar_opciones(doc, texto)
        fallos += revisar_rutas(doc, texto)
        fallos += revisar_numeros(doc, texto)
        fallos += revisar_atajos(doc, texto)
        fallos += revisar_ejemplos(doc, texto)

    fallos += revisar_motivos()

    if not fallos:
        print("%d documents checked; available checks passed."
              % len(DOCUMENTOS))
        return 0

    print("Documentation claims do not match the code:\n")
    for x in fallos:
        print("  " + x)
    return 1


if __name__ == "__main__":
    sys.exit(main())
