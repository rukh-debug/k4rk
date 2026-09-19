#!/usr/bin/env python3
"""The plugin catalog: validate the repository catalog and list the combined one.

    python3 tools/plugins.py            validate (repo + qmldir + user plugins)
    python3 tools/plugins.py --listar   emit the combined catalog as JSON

The bar loads the combined catalog: repository plugins plus user plugins in
~/.config/k4/plugins/<id>/, each with its own plugin.json. Validation lives
HERE and nowhere else: the QML manager consumes this output, and a broken
manifest marks a plugin as unloadable with a reason, rather than preventing
the bar from starting.

No QML is executed: check what can be known before starting Quickshell.
"""
from __future__ import annotations

import contextlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CATALOGO = RAIZ / "plugins" / "catalog.json"
CATALOGO_NATIVO = RAIZ / "features" / "catalog.json"
DE_USUARIO = pathlib.Path.home() / ".config" / "k4" / "plugins"

# Native host features: always-on bar chrome, not plugins. External plugins
# may not claim these ids or IPC targets.
def leer_catalogo_nativo():
    try:
        datos = json.loads(CATALOGO_NATIVO.read_text())
        return [m.get("id") for m in datos.get("features") or [] if m.get("id")]
    except OSError:
        return []

IDS_NATIVOS = {"idle", "volume", "sound", "clock", "player", "toast",
               "panel", "session", "tray"}
IPC_NATIVOS = {"k4", "k4.panel", "k4.sound", "k4.session", "k4.tray"}

RE_ID = re.compile(r"[a-z0-9][a-z0-9-]*")

#  All forty lowercase characters. Short SHAs and branches are deliberately
#  rejected: pinning ensures the installed code is exactly what was reviewed,
#  whereas a branch can move after review.
RE_SHA = re.compile(r"[0-9a-f]{40}")

#  What an external plugin may request, and what reveals each permission in QML.
#
#  This is not a sandbox and makes no such claim: QML in the same process can
#  do anything the bar can do. It provides informed consent — users see the
#  plugin's declarations before enabling it — plus analysis that turns
#  oversights and simple deception into installation errors.
#  Effects matter, not modules: reading volume changes nothing, but setting
#  it does, so we check `ponerVolumen`, not `K4.Audio`. The clipboard is the
#  exception: READING is sensitive because it holds passwords and tokens, so
#  merely referencing it requires permission.
PERMISOS = {
    #  `K4.Terminal.ejecutar` and `.abrir` execute a script; delegating the
    #  launch does not change that. Inspecting the terminal through `cual`,
    #  `enLaIsla`, or `cierre` requires no permission.
    "procesos": re.compile(r"\bK4\.Process\b|\bexecDetached\b"
                           r"|\bK4\.Terminal\.(ejecutar|abrir)\b"),
    "red": re.compile(r"\bXMLHttpRequest\b|\bWebSocket\b"),
    "ficheros": re.compile(r"\bK4\.Fichero\b"),
    "audio": re.compile(r"\bK4\.Audio\.(ponerVolumen|alternarSilencio)\b"),
    "medios": re.compile(r"\bK4\.Medios\."
                         r"(alternarPausa|siguiente|anterior|buscar)\b"),
    "notificaciones": re.compile(r"\bK4\.Notificaciones\.limpiar\b"),
    "portapapeles": re.compile(r"\bK4\.Portapapeles\b"),
    "sound": re.compile(r"\bK4\.Sonido\b"),
    #  Injecting pages into the Settings window is UI power: it gets its
    #  own line in the consent card, so «what it adds» is a promise the
    #  user read before the switch.
    "paginas": re.compile(r"\bK4\.Pagina\b"),
}

#  And WHAT each plugin is: where it draws and how it can be called.
#
#  Permissions describe what it can TOUCH; surfaces describe what it OCCUPIES.
#  The host previously inferred this from side effects — setting `view` or
#  creating a `K4.Ventana`. That has two costs: Settings cannot describe a
#  plugin without loading it, and unrequested surfaces cannot be denied.
#
#  Declarations are optional: a manifest without surfaces remains valid and
#  makes no promise. Once declared, they are binding.
#  ── named rules ──────────────────────────────────────────────────────
#
#  Permissions describe which k4 APIs a plugin touches. These rules instead
#  detect patterns anywhere — QML or bundled scripts — that can make the code
#  eventually executed differ from what someone reviewed.
#
#  Every rule explains why it matters and how to fix it. A warning without
#  an actionable fix gets ignored and serves no purpose.
#
#  `bloquea` prevents PUBLICATION, not installation. Installing your own
#  plugin on your machine is your choice; the registry must not serve
#  strangers code that downloads and executes whatever is currently online.
#
#  Other rules flag submissions for human review without blocking them.
#  Requesting `procesos` is normal — much of the bar runs commands — but
#  deserves review before approval.

REGLAS = [
    {
        "id": "descarga-y-ejecuta",
        "que": "Downloads content from the internet and pipes it to a shell",
        "porque": "The executed code is whatever that URL currently serves,"
                  " not what was reviewed. Whoever controls the URL controls"
                  " the machine where the plugin is installed.",
        "arreglo": ["Download, verify, and execute the file as separate steps.",
                    "Better yet, include it in the plugin repository so it is"
                    " tied to the commit."],
        "bloquea": True,
        "patron": re.compile(r"(?:curl|wget)[^\n|;]*\|\s*(?:sudo\s+)?"
                             r"(?:ba|z|k)?sh\b"),
    },
    {
        "id": "clon-sin-commit",
        "que": "Clones a repository without pinning the commit",
        "porque": "Branches and tags can move. Next week's executed code may"
                  " differ from what was reviewed today.",
        "arreglo": ["Supply the full SHA and check it out with `checkout`.",
                    "Update that SHA in your own commit when you want to"
                    " upgrade."],
        #  Deliberately nonblocking: proving a clone is pinned is difficult
        #  because `checkout` may appear three lines later. A false positive
        #  would block correct code. Flag it for a person who can read ahead.
        "bloquea": False,
        "patron": re.compile(r"git\s+clone(?![^\n]*[0-9a-f]{40})"
                             r"[^\n]*(?:https?://|git@)"),
    },
    {
        "id": "sudo-sin-contrasena",
        "que": "Requests root access without anyone entering a password",
        "porque": "Any process running as your user can invoke this as root,"
                  " and plugins are not sandboxed.",
        "arreglo": ["Require real authentication, or remove it.",
                    "Do not allow wildcards or externally supplied arguments."],
        "bloquea": True,
        "patron": re.compile(r"\bNOPASSWD\b|\bsudo\s+-n\b|\bpkexec\b"),
    },
    {
        "id": "qml-desde-texto",
        "que": "Constructs QML from a string at runtime",
        "porque": "The executed code is not in the repository, so reviewing"
                  " it cannot establish its behavior. External strings from"
                  " files or responses make this worse.",
        "arreglo": ["Use a `Loader` with a component from the repository.",
                    "For varying layouts, create several components and select one."],
        "bloquea": False,
        "patron": re.compile(r"\bQt\.createQmlObject\b|\beval\s*\("
                             r"|\bnew\s+Function\s*\("),
    },
    {
        "id": "borra-a-lo-ancho",
        "que": "Deletes recursively using wildcards or external paths",
        "porque": "An empty variable in `rm -rf` can delete the wrong target."
                  " This has happened in projects with far more reviewers.",
        "arreglo": ["Delete specific paths inside the plugin folder.",
                    "Check that the variable is nonempty before using it."],
        "bloquea": False,
        "patron": re.compile(r"rm\s+-[a-z]*[rR][a-z]*f|rm\s+-[a-z]*f[a-z]*[rR]"),
    },
]

#  Scan anything bundled with the plugin that could be executed. Markdown is
#  not executable, and a README example of `curl | sh` is not plugin behavior.
EJECUTABLES = (".qml", ".js", ".sh", ".bash", ".zsh", ".py", ".mjs")


def revisar_reglas(carpeta):
    """Return rule violations in the folder, including their locations."""
    fuera = []
    for ruta in sorted(pathlib.Path(carpeta).rglob("*")):
        if not ruta.is_file() or ruta.suffix.lower() not in EJECUTABLES:
            continue
        try:
            texto = ruta.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = str(ruta.relative_to(carpeta))
        for regla in REGLAS:
            for m in regla["patron"].finditer(texto):
                fuera.append({
                    "id": regla["id"],
                    "que": regla["que"],
                    "porque": regla["porque"],
                    "arreglo": regla["arreglo"],
                    "bloquea": regla["bloquea"],
                    "donde": "%s:%d" % (rel, texto[:m.start()].count("\n") + 1),
                })
                break   # Once per file and rule; further matches add noise.
    return fuera


SUPERFICIES = {
    #  Draws in the island: it has a view.
    "island": re.compile(r"^\s*view\s*:", re.MULTILINE),
    #  Displays content in the pill even while closed.
    "pildora": re.compile(r"\bK4\.Pildora\b"),
    #  Draws OUTSIDE the island, on its own surface.
    "ventana": re.compile(r"\bK4\.Ventana\b"),
    #  Can be called externally.
    "ipc": re.compile(r"\bK4\.Ipc\b"),
    #  Contributes a block to the control center.
    "centro": re.compile(r"\bK4\.Card\b"),
}


#  The COMMANDS a plugin registers: IPC targets for external calls.
#
#  Read QML rather than the manifest because it defines actual registrations:
#  regardless of declarations, the written `K4.Ipc` claims `k4.notas`. As with
#  permissions, inspect source rather than trusting declarations, here to
#  determine ownership across plugins.
#
#  The 400-character window is a deliberate compromise: QML normally puts
#  `target` and `name` in the first two lines. Matching nested braces with a
#  regex is worse than this limit. A target hidden five hundred characters
#  later is missed, and its collision will appear only in the log as before.
RE_IPC_BLOQUE = re.compile(r"\bK4\.Ipc\b\s*\{")
RE_TARGET = re.compile(r"\btarget\s*:\s*[\"']([^\"']+)[\"']")


def comandos_de_texto(texto, ipc):
    """Add the targets registered by this QML to `ipc`."""
    for m in RE_IPC_BLOQUE.finditer(texto):
        hallado = RE_TARGET.search(texto[m.end():m.end() + 400])
        if hallado:
            ipc.add(hallado.group(1))


def comandos_de_carpeta(d):
    """Return `{"ipc": [...]}` for a plugin folder."""
    ipc = set()
    for qml in d.glob("**/*.qml"):
        try:
            texto = "\n".join(re.sub(r"//.*$", "", l)
                              for l in qml.read_text().split("\n"))
        except OSError:
            continue
        comandos_de_texto(texto, ipc)
    return {"ipc": sorted(ipc)}


def marcar_choques(combinado):
    """Mark plugins unloadable when they claim an already-owned command.

    The first entry in the combined catalog wins, and repository plugins
    come first. External plugins therefore cannot take their commands,
    following the same precedence rule as ids.

    Otherwise collisions are invisible: Quickshell registers the first and
    leaves the second inactive, reporting it only in the log. The plugin
    appears loaded without errors but its commands never respond.
    """
    dueno = {t: "nativo" for t in IPC_NATIVOS}
    for item in combinado:
        if not item.get("cargable", True):
            continue
        cmds = item.get("comandos") or {}
        ident = item.get("id")
        for t in cmds.get("ipc") or []:
            if t in dueno:
                item["cargable"] = False
                item["motivo"], item["dice"], item["detalle"] = (
                    "comando-ocupado",
                    f"command {t} is already registered by «{dueno[t]}»", t)
                break
        else:
            for t in cmds.get("ipc") or []:
                dueno[t] = ident
    return combinado


def version_tupla(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return None


def host_compatible(requisito, version_host):
    """Compare `>=x.y.z` with the bar version; no requirement means compatible."""
    if not requisito:
        return True
    m = re.fullmatch(r">=\s*(\d+(?:\.\d+)*)", str(requisito).strip())
    if not m:
        return False
    pedido = version_tupla(m.group(1))
    real = version_tupla(version_host)
    return pedido is not None and real is not None and real >= pedido


def leer_catalogo():
    datos = json.loads(CATALOGO.read_text())
    return datos, [normalizar(p) for p in datos.get("plugins") or []]


#  The manifest vocabulary is English now; the Spanish keys it grew up
#  with are read as aliases so nothing already in the wild breaks on the
#  rename. English wins when both are present.
ALIAS = {
    "require": "requiere",
    "icon": "icono",
    "permissions": "permisos",
    "application": "aplicacion",
    "surfaces": "superficies",
}


def normalizar(m):
    """One vocabulary: English keys, with the Spanish ones honored as aliases."""
    n = dict(m)
    for ingles, viejo in ALIAS.items():
        if ingles not in n and viejo in m:
            n[ingles] = m[viejo]
        n.pop(viejo, None)
    return n


def validar_nativo(fallos):
    """Native host features: fixed ids, existing entries, complete qmldir."""
    try:
        datos = json.loads(CATALOGO_NATIVO.read_text())
    except Exception as exc:
        fallos.append(f"features/catalog.json unreadable: {exc}")
        return set()
    feats = datos.get("features") or []
    ids: set[str] = set()
    ordenes: set[int] = set()
    for item in feats:
        ident = item.get("id")
        entrada = item.get("entry")
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
            fallos.append(f"invalid native id: {ident!r}")
            continue
        if ident in ids:
            fallos.append(f"duplicate native id: {ident}")
        ids.add(ident)
        if ident not in IDS_NATIVOS:
            fallos.append(f"native {ident}: id is not reserved")
        orden = item.get("order")
        if not isinstance(orden, int) or orden in ordenes:
            fallos.append(f"native {ident}: duplicate or invalid order")
        else:
            ordenes.add(orden)
        if not isinstance(entrada, str):
            fallos.append(f"native {ident}: missing entry")
            continue
        ruta = (CATALOGO_NATIVO.parent / str(entrada)).resolve()
        try:
            ruta.relative_to(RAIZ)
        except ValueError:
            fallos.append(f"native {ident}: entry outside the repository")
            continue
        if not ruta.is_file():
            fallos.append(f"native {ident}: {entrada} does not exist")
            continue
        texto = ruta.read_text()
        if "pragma Singleton" not in texto or "Singleton {" not in texto:
            fallos.append(f"native {ident}: root must be a Singleton")
        if "Quickshell" not in texto:
            fallos.append(f"native {ident}: missing import Quickshell "
                          "(Singleton is not a type without it)")
        if ("IpcHandler" in texto or "Process" in texto
                or "FileView" in texto or "StdioCollector" in texto
                or "SplitParser" in texto) and "Quickshell.Io" not in texto:
            fallos.append(f"native {ident}: missing import Quickshell.Io")
    if ids != IDS_NATIVOS - {"tray"}:
        fallos.append(f"native: ids {sorted(ids)} != expected {sorted(IDS_NATIVOS - {'tray'})}")
    # services/ and core/ qmldir stay complete for native singletons/views.
    for qmldir_rel in ["services/qmldir", "core/qmldir"]:
        qmldir = RAIZ / qmldir_rel
        if not qmldir.is_file():
            fallos.append(f"missing {qmldir_rel}")
    return ids


def validar_repo(plugins, fallos):
    """Validate repository plugins: catalog, name, folder, and current qmldir."""
    nativos = validar_nativo(fallos)
    ids: set[str] = set()
    for item in plugins:
        ident = item.get("id")
        entrada = item.get("entry")
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
            fallos.append(f"invalid id: {ident!r}")
            continue
        if ident in ids:
            fallos.append(f"duplicate id: {ident}")
        ids.add(ident)
        if not isinstance(entrada, str):
            fallos.append(f"{ident}: missing entry")
            continue
        ruta = RAIZ / "plugins" / entrada
        if not ruta.is_file():
            fallos.append(f"{ident}: {entrada} does not exist")
            continue
        texto = ruta.read_text()
        nombres = re.findall(r"^\s{4}name\s*:\s*['\"]([^'\"]+)['\"]\s*$",
                             texto, re.MULTILINE)
        if len(nombres) != 1:
            fallos.append(f"{ident}: must declare exactly one name")
        elif nombres[0] != ident:
            fallos.append(f"{ident}: QML name is {nombres[0]!r}")

        #  House plugins get the same honesty the door demands of strangers:
        #  what they touch declared, what they are said out loud, an icon to
        #  be found by. Repo manifests are written by hand, and hands drift.
        desc = item.get("description")
        if not isinstance(desc, str) or not desc.strip():
            fallos.append(f"{ident}: missing description")
        icono = item.get("icon")
        if not isinstance(icono, str) or not icono:
            fallos.append(f"{ident}: missing icon")
        elif not re.fullmatch(r"0[xX][0-9a-fA-F]{4,6}", icono) \
                and not ((RAIZ / "plugins" / str(entrada)).parent / icono).is_file():
            fallos.append(f"{ident}: icon is neither a code point nor a file")
        declarados = set(item.get("permissions") or [])
        raros = declarados - set(PERMISOS)
        if raros:
            fallos.append(f"{ident}: unknown permissions: "
                          + ", ".join(sorted(raros)))
        usados = set()
        for qml in (RAIZ / "plugins" / str(entrada)).parent.glob("**/*.qml"):
            cuerpo = "\n".join(re.sub(r"//.*$", "", l)
                               for l in qml.read_text().split("\n"))
            for permiso, patron in PERMISOS.items():
                if patron.search(cuerpo):
                    usados.add(permiso)
        sin_declarar = usados - declarados
        if sin_declarar:
            fallos.append(f"{ident}: uses without declaring: "
                          + ", ".join(sorted(sin_declarar)))

    for duplicado in sorted(ids & nativos):
        fallos.append(f"id {duplicado}: both a native feature and a plugin")

    carpetas = {p.name for p in (RAIZ / "plugins").iterdir()
                if p.is_dir() and (p / (p.name + "Plugin.qml")).is_file()}
    en_catalogo = {str(item.get("entry", "")).split("/", 1)[0]
                   for item in plugins}
    for carpeta in sorted(carpetas - en_catalogo):
        fallos.append(f"plugin missing from catalog: {carpeta}")

    #  Each folder's qmldir must list ALL its .qml files: Quickshell's URL
    #  scheme has no implicit sibling resolution, so missing types cause
    #  "X is not a type" at load time. These were generated for dynamic
    #  loading; this check keeps them current.
    for carpeta in sorted(carpetas):
        d = RAIZ / "plugins" / carpeta
        qmldir = d / "qmldir"
        if not qmldir.is_file():
            fallos.append(f"{carpeta}: missing qmldir")
            continue
        declarados = set(re.findall(r"^(\w+) 1\.0", qmldir.read_text(),
                                    re.MULTILINE))
        reales = {f.stem for f in d.glob("*.qml")}
        for falta in sorted(reales - declarados):
            fallos.append(f"{carpeta}/qmldir: missing {falta}")
    return ids


#  Accepted image icons and the reason for the minimum size.
#
#  The app center renders icons at 64 px on a normal display. Smaller images
#  look blurry exactly where users focus; a pixelated icon makes a good plugin
#  look bad. SVG has no minimum because it scales.
ICONO_MINIMO = 64
ICONO_MAXIMO_MB = 1
ICONO_MAXIMO_BYTES = ICONO_MAXIMO_MB * 1024 * 1024


def medida_png(ruta):
    """Read PNG width and height from its header, without dependencies.
    It takes twenty-four bytes and the format has been stable for decades."""
    with open(ruta, "rb") as f:
        cab = f.read(24)
    if len(cab) < 24 or cab[:8] != b"\x89PNG\r\n\x1a\n" or cab[12:16] != b"IHDR":
        return None
    return (int.from_bytes(cab[16:20], "big"), int.from_bytes(cab[20:24], "big"))


def revisar_icono(carpeta, icono, item):
    """Validate the declared icon. Return a failure explanation, or None.

    Populate `item` with what the bar needs: `icon` for a code point or
    `iconFile` (absolute path) for an image. Separate them here so QML does
    not need to guess which kind it received.
    """
    if not isinstance(icono, str) or not icono:
        return f"icon must be a code point or a file, not {icono!r}"

    if re.fullmatch(r"0[xX][0-9a-fA-F]{4,6}", icono):
        item["icon"] = icono
        return None

    #  A file in the plugin's own folder: no absolute paths or traversal.
    #  A plugin must own its icon.
    if "/" in icono or icono.startswith("."):
        return "the icon must be a file in your folder, without a path"
    ext = icono.lower().rsplit(".", 1)[-1] if "." in icono else ""
    if ext not in ("png", "svg"):
        return f"icon {icono!r}: only PNG or SVG (or a code point like 0xF04E5)"

    ruta = carpeta / icono
    if not ruta.is_file():
        return f"icon {icono} does not exist"
    if ruta.stat().st_size > ICONO_MAXIMO_BYTES:
        return (f"the icon is {ruta.stat().st_size // 1024} KB; the limit is "
                f"{ICONO_MAXIMO_BYTES // 1024} KB")

    if ext == "png":
        medida = medida_png(ruta)
        if medida is None:
            return f"{icono} is not a valid PNG"
        ancho, alto = medida
        if ancho < ICONO_MINIMO or alto < ICONO_MINIMO:
            return (f"the icon is {ancho}x{alto} and the minimum is "
                    f"{ICONO_MINIMO}x{ICONO_MINIMO}: smaller images look "
                    f"blurry exactly where users focus")

    item.pop("icon", None)
    item["iconFile"] = str(ruta)
    return None


def validar_carpeta(d, ids_repo, version_host):
    """Return the verdict for ONE plugin folder: `{…, cargable, motivo}`.

    Works for installed plugins and fresh clones not yet placed in
    ~/.config/k4/plugins, allowing validation BEFORE installation rather than
    installing first and seeing what happens.
    """
    item = {"id": d.name, "title": d.name, "externo": True,
            "enabledByDefault": False, "cargable": True,
            "permissions": [], "version": "0"}

    #  Two representations, both necessary:
    #
    #  `motivo` is a CODE for the bar to turn into a message. `dice` is the
    #  English explanation for terminal users, this script's audience, who
    #  should not have to decipher codes.
    #
    #  Previously only the explanation existed and leaked into the UI,
    #  producing English titles with Spanish reasons underneath.
    def mal(codigo, dice, detalle=""):
        item["cargable"] = False
        item["motivo"] = codigo
        item["dice"] = dice
        if detalle:
            item["detalle"] = detalle
        return item

    manifiesto = d / "plugin.json"
    if not manifiesto.is_file():
        return mal("sin-manifiesto", "missing plugin.json")
    try:
        m = normalizar(json.loads(manifiesto.read_text()))
    except Exception as exc:
        return mal("manifiesto-ilegible", f"plugin.json unreadable: {exc}",
                   str(exc))

    for clave in ("id", "title", "version", "description", "permissions", "host",
                  "application"):
        if clave in m:
            item[clave] = m[clave]
    ident = m.get("id")
    if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
        return mal("id-invalido", f"invalid id: {ident!r}", str(ident))
    if ident != d.name:
        return mal("id-no-coincide",
                   f"id {ident!r} does not match folder {d.name!r}",
                   f"{ident} / {d.name}")
    if ident in IDS_NATIVOS:
        return mal("id-nativo", f"id {ident!r} is a native bar feature",
                   ident)
    if ident in ids_repo:
        return mal("id-ocupado", "the id is already used by a bar plugin")
    entrada = m.get("entry")
    if not isinstance(entrada, str) or "/" in entrada:
        return mal("entrada-fuera",
                   "entry must be a file in the plugin's own folder")
    ruta = d / entrada
    if not ruta.is_file():
        return mal("sin-entrada", f"{entrada} does not exist", str(entrada))
    if not host_compatible(m.get("host"), version_host):
        return mal("barra-vieja",
                   f"requires bar {m.get('host')}, this is {version_host}",
                   str(m.get("host") or ""))

    #  The icon may be a Nerd Font code point or a bundled image. Validate it
    #  here so a bad icon causes an installation error rather than an empty
    #  square in the app center.
    if m.get("icon") is not None:
        fallo = revisar_icono(d, m.get("icon"), item)
        if fallo:
            #  Icon validation supplies its own explanation; the shared code
            #  covers all variants of "that icon is invalid".
            return mal("icono-malo", fallo)

    #  Permission analysis: actual QML usage versus declarations.
    declarados = set(m.get("permissions") or [])
    raros = declarados - set(PERMISOS)
    if raros:
        return mal("permisos-raros",
                   "unknown permissions: " + ", ".join(sorted(raros)),
                   ", ".join(sorted(raros)))
    usados = set()
    for qml in d.glob("**/*.qml"):
        texto = "\n".join(re.sub(r"//.*$", "", l)
                           for l in qml.read_text().split("\n"))
        for permiso, patron in PERMISOS.items():
            if patron.search(texto):
                usados.add(permiso)
    sin_declarar = usados - declarados
    if sin_declarar:
        return mal("sin-declarar",
                   "uses without declaring: " + ", ".join(sorted(sin_declarar)),
                   ", ".join(sorted(sin_declarar)))

    #  Surfaces: what it OCCUPIES versus what it TOUCHES.
    #
    #  Deliberately optional: a manifest without surfaces remains valid and
    #  makes no promise, preserving compatibility with older plugins. Once
    #  declared, surfaces are checked against actual QML behavior, making
    #  them useful rather than decorative manifest metadata.
    sup_declaradas = m.get("surfaces")
    if sup_declaradas is not None:
        sup_declaradas = set(sup_declaradas or [])
        #  Forward them to the result instead of validating and discarding
        #  them. The store and submission report used to receive an empty
        #  list despite declarations. Surfaces matter only if users can SEE
        #  them before enabling the plugin.
        item["surfaces"] = sorted(sup_declaradas)
        raras = sup_declaradas - set(SUPERFICIES)
        if raras:
            return mal("superficies-raras",
                       "unknown surfaces: " + ", ".join(sorted(raras)),
                       ", ".join(sorted(raras)))
        sup_usadas = set()
        for qml in d.glob("**/*.qml"):
            texto = "\n".join(re.sub(r"//.*$", "", l)
                               for l in qml.read_text().split("\n"))
            for sup, patron in SUPERFICIES.items():
                if patron.search(texto):
                    sup_usadas.add(sup)
        faltan = sup_usadas - sup_declaradas
        if faltan:
            return mal("superficie-sin-declarar",
                       "occupies without declaring: " + ", ".join(sorted(faltan)),
                       ", ".join(sorted(faltan)))

    #  Record registered commands for display and for `marcar_choques` to
    #  compare with other plugins. Native targets belong to the host and
    #  cannot be claimed.
    item["comandos"] = comandos_de_carpeta(d)
    nativos = set(item["comandos"].get("ipc") or []) & IPC_NATIVOS
    if nativos:
        return mal("comando-nativo",
                   "command " + sorted(nativos)[0] + " belongs to the bar",
                   sorted(nativos)[0])

    #  Generate qmldir when missing or outdated: Quickshell's URL scheme
    #  cannot resolve sibling types implicitly. Requiring authors to maintain
    #  this list manually invites "X is not a type" on the first new file.
    reales = sorted(f.stem for f in d.glob("*.qml"))
    qmldir = d / "qmldir"
    declarados_qml = (set(re.findall(r"^(\w+) 1\.0", qmldir.read_text(),
                                     re.MULTILINE))
                      if qmldir.is_file() else set())
    if set(reales) - declarados_qml:
        try:
            qmldir.write_text(
                "#  Generated: the types in this folder, so they also resolve\n"
                "#  when the plugin is loaded by URL (the qs: scheme), where the\n"
                "#  implicit resolution of siblings does not exist.\n"
                "#  `python3 tools/plugins.py` checks that it stays complete.\n"
                "\n"
                + "".join(f"{n} 1.0 {n}.qml\n" for n in reales))
        except OSError:
            return mal("sin-qmldir", "cannot write qmldir")

    #  Loadable. Emit an ABSOLUTE entry path: the manager need not know where
    #  user plugins live.
    item["entry"] = str(ruta)
    return item


def cargar_usuario(ids_repo, version_host):
    """Return plugins in ~/.config/k4/plugins, each with its verdict.

    A broken user plugin is never a repository failure: list it with
    `cargable: false` and a reason, so Settings can display it and the manager
    can skip loading it. Repository ids take precedence: external plugins
    cannot impersonate bundled ones.
    """
    if not DE_USUARIO.is_dir():
        return []
    fuera = []
    for d in sorted(DE_USUARIO.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        item = validar_carpeta(d, ids_repo, version_host)
        #  Mark ownership for the bar: bundled plugins cannot be removed or
        #  updated, and the store needs to distinguish them without guessing
        #  from ids. Set it here, where the origin is known.
        item["deUsuario"] = True
        fuera.append(item)
    return fuera


def enlazar_externos():
    """Bridge user plugins into the bar through a symlink in the shell tree.

    Quickshell serves its configuration under its own URL scheme. QML loaded
    through file:// creates ITS OWN copies of every singleton: two
    PluginManagers, duplicate services, and every IPC target registered twice.
    The symlink places user plugins inside the tree from the engine's point
    of view, sharing the scheme and singletons. One symlink avoids duplicating
    the entire bar.
    """
    DE_USUARIO.mkdir(parents=True, exist_ok=True)
    enlace = RAIZ / "externos"
    try:
        if enlace.is_symlink():
            if enlace.readlink() != DE_USUARIO:
                enlace.unlink()
                enlace.symlink_to(DE_USUARIO)
        elif not enlace.exists():
            enlace.symlink_to(DE_USUARIO)
    except OSError:
        pass


#  An installed plugin's provenance: its source and, crucially, ITS COMMIT.
#  Previously `.origen` held only a URL, which could not answer "which version
#  is installed?" or "has the repository changed since installation?". Keep
#  reading the old format for compatibility; the first update writes the new
#  format.
ORIGEN = ".origen.json"


def leer_origen(ident):
    """Read an installed plugin's provenance in the current or legacy format."""
    d = DE_USUARIO / ident
    nuevo = d / ORIGEN
    if nuevo.is_file():
        try:
            o = json.loads(nuevo.read_text())
            if isinstance(o, dict) and o.get("repo"):
                #  `folder` is the key of record now; papers written by
                #  older installs say `carpeta`, and both are honored.
                if "folder" not in o and "carpeta" in o:
                    o["folder"] = o["carpeta"]
                return o
        except Exception:
            pass
    viejo = d / ".origen"
    if viejo.is_file():
        #  Legacy format: only a URL, with no commit or folder. Omitting the
        #  folder was a bug: updates had to rediscover repository subfolders.
        return {"repo": viejo.read_text().strip()}
    return None


def escribir_origen(destino, repo, subcarpeta, commit, item):
    (destino / ORIGEN).write_text(json.dumps({
        "repo": repo,
        "folder": subcarpeta or "",
        "commit": commit or "",
        "version": item.get("version", "0"),
        "cuando": int(time.time()),
    }, ensure_ascii=False, indent=1) + "\n")


def _contexto():
    """Return the context for validation: repository ids and host version."""
    datos, plugins = leer_catalogo()
    return ({item.get("id") for item in plugins},
            str(datos.get("version", "1.0.0")))


def _commit_de(clon):
    """Return the clone's current commit, or an empty string if unknown."""
    try:
        p = subprocess.run(["git", "-C", str(clon), "rev-parse", "HEAD"],
                           capture_output=True, text=True, timeout=20)
        sha = p.stdout.strip()
        return sha if RE_SHA.fullmatch(sha) else ""
    except Exception:
        return ""


def _ir_al_commit(clon, url, commit):
    """Check out EXACTLY that commit and return whether it succeeded."""
    g = ["git", "-C", str(clon)]
    #  Already available? This happens when the requested commit is the tip.
    try:
        if subprocess.run(g + ["cat-file", "-e", commit + "^{commit}"],
                          capture_output=True, timeout=20).returncode == 0:
            return subprocess.run(g + ["checkout", "-q", "--detach", commit],
                                  capture_output=True, timeout=60).returncode == 0
    except Exception:
        return False
    #  Otherwise fetch it directly. If the server will not serve individual
    #  commits, fetch the full history: slower, but necessary to guarantee
    #  that the installed code is what was reviewed.
    for traer in (["fetch", "-q", "--depth", "1", url, commit],
                  ["fetch", "-q", "--unshallow"],
                  ["fetch", "-q", url]):
        try:
            subprocess.run(g + traer, capture_output=True, timeout=600)
            if subprocess.run(g + ["checkout", "-q", "--detach", commit],
                              capture_output=True,
                              timeout=60).returncode == 0:
                return True
        except Exception:
            continue
    return False


def _carpeta_del_clon(base):
    """Locate the plugin inside the clone.

    Accept plugin.json at the root, as in a typical one-plugin repository,
    or in a single subfolder, as in repositories containing an example.
    With multiple candidates, require the user to choose instead of guessing.
    """
    if (base / "plugin.json").is_file():
        return base
    candidatos = [d for d in sorted(base.iterdir())
                  if d.is_dir() and (d / "plugin.json").is_file()]
    if len(candidatos) == 1:
        return candidatos[0]
    return None


def _describir(item):
    lineas = [f"  {item.get('title', item['id'])}  ·  {item['id']}"
              f"  ·  v{item.get('version', '0')}"]
    if item.get("description"):
        lineas.append(f"  {item['description']}")
    permisos = item.get("permissions") or []
    lineas.append("  Permissions: " + (", ".join(permisos) if permisos
                                       else "none"))
    return "\n".join(lineas)


class Traido:
    """The result of fetching and examining a repo: a valid plugin or a reason.

    `motivo` is a CODE, with data in `detalle`, so the presentation layer can
    write the explanation. See `Motivos.porque()`.
    """

    def __init__(self, ok, motivo="", carpeta=None, item=None, commit="",
                 detalle=""):
        self.ok = ok
        self.motivo = motivo
        self.detalle = detalle
        self.carpeta = carpeta
        self.item = item
        self.commit = commit

    def contar(self):
        """Format the reason and details for a person using a terminal."""
        return self.motivo + (": " + self.detalle if self.detalle else "")


@contextlib.contextmanager
def _traer(url, subcarpeta=None, commit=None):
    """Clone, pin, locate the plugin, and validate it.

    Shared by TWO operations: installation and the examination requested by
    the bar before displaying permissions. They must behave identically: if
    examination and installation fetched different code, the permissions
    dialog would lie. Examination therefore returns its commit for the bar
    to pass as a pin, installing exactly what was shown.

    Yield a `Traido` while the temporary directory exists; remove it on exit.
    """
    ids_repo, version_host = _contexto()
    with tempfile.TemporaryDirectory(prefix="k4-plugin-") as tmp:
        clon = pathlib.Path(tmp) / "clon"
        #  Use `--depth 1` only for remote clones. Git warns that it is ignored
        #  for local clones, which looks like an error in the permissions UI.
        orden = ["git", "clone", "-q"]
        if "://" in url and not url.startswith("file://"):
            orden += ["--depth", "1"]
        try:
            subprocess.run(orden + [url, str(clon)], check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            yield Traido(False, "sin-clonar", detalle=f"{url}: {exc}")
            return

        #  Check out the requested commit, not the branch tip. A shallow clone
        #  may lack it, requiring a separate fetch. If the server does not
        #  serve individual SHAs — GitHub does — fall back to the full clone.
        if commit:
            if not RE_SHA.fullmatch(commit):
                yield Traido(False, "commit-raro", detalle=str(commit))
                return
            if not _ir_al_commit(clon, url, commit):
                yield Traido(False, "sin-commit",
                             detalle="%s · %s" % (commit[:12], url))
                return

        #  ALWAYS record the SHA, requested or not: it answers "what exactly
        #  is installed?". After removing `.git`, that information is gone.
        traido = _commit_de(clon)
        shutil.rmtree(clon / ".git", ignore_errors=True)

        carpeta = (clon / subcarpeta) if subcarpeta else _carpeta_del_clon(clon)
        if carpeta is None or not carpeta.is_dir():
            yield Traido(False, "sin-plugin")
            return

        #  The id takes precedence over the clone's name: the folder starts
        #  with the repository name, but validation requires it to match the id.
        try:
            ident = json.loads((carpeta / "plugin.json").read_text())["id"]
        except Exception as exc:
            yield Traido(False, "ilegible", detalle=str(exc))
            return
        if isinstance(ident, str) and RE_ID.fullmatch(ident) \
                and carpeta.name != ident:
            nueva = carpeta.parent / ident
            if nueva.exists():
                shutil.rmtree(nueva)
            carpeta = carpeta.rename(nueva)

        item = validar_carpeta(carpeta, ids_repo, version_host)
        if not item.get("cargable"):
            yield Traido(False, "no-cargable",
                         detalle=str(item.get("dice")
                                     or item.get("motivo") or ""),
                         commit=traido)
            return

        yield Traido(True, "", carpeta, item, traido)


def instalar(url, sin_preguntar=False, subcarpeta=None, commit=None):
    """Clone, validate, and — with consent — install an external plugin.

    Order matters: clone into a temporary directory, validate EVERYTHING
    there, then display declarations and request consent. Nothing reaches
    ~/.config/k4/plugins without the same validation as installed plugins,
    avoiding a "half-installed and broken" state.

    It always arrives DISABLED. Installation fetches it; enabling it is a
    separate decision made in Settings with these same permissions visible.
    """
    with _traer(url, subcarpeta, commit) as t:
        if not t.ok:
            print(t.contar(), file=sys.stderr)
            return 1
        carpeta, item, traido = t.carpeta, t.item, t.commit

        destino = DE_USUARIO / item["id"]
        print(f"\nFrom {url}:\n")
        print(_describir(item))
        if traido:
            #  Show the commit BEFORE asking for consent: it is part of what
            #  users accept. Trusting a repository differs from trusting code.
            print(f"  Commit:   {traido[:12]}"
                  + ("  (as requested)" if commit else "  (branch tip)"))
        anterior = leer_origen(item["id"]) or {}
        print("\n  Will install into", destino)
        print("  Arrives disabled: enable it in Settings.")
        if destino.exists():
            print("  ALREADY EXISTS: the installed version will be replaced.")
        print()
        #  Show warnings BEFORE the standard notice and consent prompt:
        #  nobody reads them after "Install? [y/N]".
        avisos = revisar_reglas(carpeta)
        if avisos:
            print()
            for a in avisos:
                print("  %s %s" % ("BLOCKS  " if a["bloquea"] else "warning:",
                                   a["que"]))
                print("           at %s" % a["donde"])
                print("           %s" % a["porque"])
        print()
        print("  A plugin runs inside the bar and can do anything the bar")
        print("  can do. Permissions are its DECLARATIONS, not a sandbox:")
        print("  installing it means trusting its author.")
        if not sin_preguntar:
            try:
                if input("\nInstall? [y/N] ").strip().lower() not in ("y", "yes", "s", "si", "sí"):
                    print("nothing installed.")
                    return 1
            except EOFError:
                print("no terminal for confirmation; use --yes if you are sure.",
                      file=sys.stderr)
                return 1

        DE_USUARIO.mkdir(parents=True, exist_ok=True)
        reemplaza = destino.exists()
        if reemplaza:
            shutil.rmtree(destino)
        shutil.copytree(carpeta, destino)
        escribir_origen(destino, url, subcarpeta, traido, item)

    ident = item["id"]
    if reemplaza:
        print(f"\nupdated: {ident} v{item.get('version', '0')}.")
        antes = (anterior.get("commit") or "")[:12]
        if traido and antes and antes != traido[:12]:
            print(f"  {antes} → {traido[:12]}")
        elif traido and antes:
            print(f"  still at {traido[:12]}: nothing new was available.")
        #  If enabled, the bar still runs the old code: disk contents changed,
        #  but the live instance did not.
        print(f"  If it was enabled: `k4 pluginReload {ident}`.")
    else:
        print(f"\ninstalled: {ident}. Enable it in Settings"
              f" (or `k4 pluginRefresh` and `k4 pluginEnable {ident}`).")
    return 0


def actualizar(ident, sin_preguntar=False, commit=None):
    """Reinstall from the original source into the correct folder.

    The folder matters: previously only the URL was saved, so updates had to
    rediscover repository subfolders, including k4's examples. Multiple
    candidates made this impossible. The folder is now recorded.

    Without `--commit`, an update fetches the branch tip as expected. With
    it, the update fetches exactly the specified commit.
    """
    o = leer_origen(ident)
    if not o:
        print(f"{ident} was not installed from a URL; its update source is "
              "unknown.", file=sys.stderr)
        return 1
    return instalar(o["repo"], sin_preguntar, o.get("folder") or None, commit)


def quitar(ident, sin_preguntar=False, con_estado=False):
    """Uninstall the folder and, if requested, its saved state."""
    d = DE_USUARIO / ident
    if not d.is_dir():
        print(f"{ident} is not installed.", file=sys.stderr)
        return 1
    estado = (pathlib.Path.home() / ".local" / "state" / "k4" / "plugins"
              / ident)
    print(f"will delete {d}")
    if con_estado and estado.is_dir():
        print(f"and its saved state in {estado}")
    if not sin_preguntar:
        try:
            if input("Are you sure? [y/N] ").strip().lower() not in ("y", "yes", "s", "si", "sí"):
                print("nothing deleted.")
                return 1
        except EOFError:
            print("no terminal for confirmation; use --yes.", file=sys.stderr)
            return 1
    shutil.rmtree(d)
    if con_estado:
        shutil.rmtree(estado, ignore_errors=True)
    print(f"removed: {ident}")
    return 0


def instalados():
    """List installed external plugins with their verdicts and sources."""
    ids_repo, version_host = _contexto()
    externos = cargar_usuario(ids_repo, version_host)
    if not externos:
        print("no user plugins installed.")
        return 0
    for item in externos:
        estado = ("ok" if item.get("cargable")
                  else "UNLOADABLE: %s" % (item.get("dice")
                                         or item.get("motivo") or "?"))
        o = leer_origen(item["id"])
        de = o["repo"] if o else "local"
        if o and o.get("folder"):
            de += "  ·  " + o["folder"]
        sha = (o or {}).get("commit") or ""
        print(f"{item['id']:<16} v{item.get('version', '0'):<8} {estado}")
        print(f"{'':<16} {de}")
        #  A missing commit means installation predates commit tracking: the
        #  source is known but the exact code is not, and users need to know.
        print(f"{'':<16} {sha[:12] if sha else 'unknown commit (installed with an older version)'}")
    return 0


def recargar(ident):
    """Create a fresh folder URL for hot reload.

    Adding `?r1` to the entry reloads only the entry. Sibling files — usually
    the view the author just edited — resolve against the SAME folder and
    come from cache. The plugin was recreated but displayed the old version,
    a subtle bug because recreation really did occur.

    Reload the whole folder instead: a fresh symlink in `recargas/` gives
    EVERYTHING inside a new URL. Each reload costs one symlink, with previous
    links for the same plugin removed.
    """
    enlazar_externos()
    datos, plugins = leer_catalogo()
    ids_repo = {item.get("id") for item in plugins}
    todos = list(plugins) + cargar_usuario(ids_repo,
                                           str(datos.get("version", "1.0.0")))
    for item in todos:
        if item.get("id") != ident:
            continue
        if not item.get("cargable", True):
            return 1
        entrada = str(item.get("entry", ""))
        origen = (pathlib.Path(entrada) if entrada.startswith("/")
                  else RAIZ / "plugins" / entrada)
        carpeta = origen.parent
        destino = RAIZ / "recargas"
        destino.mkdir(exist_ok=True)
        ronda = 1
        for viejo in destino.glob(ident + "-*"):
            try:
                ronda = max(ronda, int(viejo.name.rsplit("-", 1)[1]) + 1)
                viejo.unlink()
            except (ValueError, OSError):
                pass
        enlace = destino / f"{ident}-{ronda}"
        enlace.symlink_to(carpeta)
        print(f"recargas/{enlace.name}/{origen.name}")
        return 0
    return 1


def listar():
    enlazar_externos()
    #  Reload folders belong to the previous session and are stale at startup.
    for viejo in (RAIZ / "recargas").glob("*"):
        try:
            viejo.unlink()
        except OSError:
            pass
    datos, plugins = leer_catalogo()
    version_host = str(datos.get("version", "1.0.0"))
    ids_repo = {item.get("id") for item in plugins}

    #  Repository plugins have a handwritten catalog and skip
    #  `validar_carpeta`, so inspect their source here. Otherwise collision
    #  checks would see only external plugins, letting a user plugin silently
    #  claim the launcher's command.
    for item in plugins:
        entrada = item.get("entry")
        if not entrada:
            continue
        carpeta = (RAIZ / "plugins" / entrada).parent
        if carpeta.is_dir():
            item["comandos"] = comandos_de_carpeta(carpeta)

    combinado = marcar_choques(list(plugins)
                               + cargar_usuario(ids_repo, version_host))
    print(json.dumps({"schema": 1, "version": version_host,
                      "plugins": combinado}, ensure_ascii=False))
    return 0


#  The storefront: public JSON listing community publications. Keep it in the
#  repository to avoid a separate server; users can select another registry
#  with --registro.
REGISTRO = ("https://raw.githubusercontent.com/k4ditano/k4/main/"
            "plugins/registro.json")


def _campo(e, ingles, viejo):
    """English key first, Spanish alias honored — registries in the wild
    still speak the old shape, and a PR is not broken for a rename."""
    if ingles in e:
        return e[ingles]
    return e.get(viejo)


def leer_registro(url=None):
    """Read the published registry, raising an exception on failure."""
    import urllib.request
    with urllib.request.urlopen(url or REGISTRO, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def buscar(termino=None, url=None):
    """List registry publications, optionally filtered by a search term."""
    try:
        datos = leer_registro(url)
    except Exception as exc:
        print(f"could not read the registry: {exc}", file=sys.stderr)
        return 2

    t = (termino or "").lower()
    aciertos = [e for e in datos.get("plugins") or []
                if not t
                or t in str(e.get("id", "")).lower()
                or t in str(e.get("title", "")).lower()
                or t in str(e.get("description", "")).lower()]

    if not aciertos:
        print("nothing in the registry"
              + (f" matching {termino!r}" if t else "") + ".")
        return 1

    for e in aciertos:
        autor = _campo(e, "author", "autor")
        print(f"  {e.get('title', e.get('id'))}  ·  {e.get('id')}"
              + (f"  ·  by {autor}" if autor else ""))
        if e.get("description"):
            print(f"    {e['description']}")
        sha = str(e.get("commit") or "")
        if sha:
            print(f"    commit {sha[:12]}")
        orden = f"    install: tools/plugins.py --install {e.get('repo')}"
        carpeta = _campo(e, "folder", "carpeta")
        if carpeta:
            orden += f" --folder {carpeta}"
        #  Include the commit in the copyable command. Otherwise users install
        #  the branch tip and pinning serves no purpose.
        if sha:
            orden += f" --commit {sha}"
        print(orden + "\n")
    return 0


FICHERO_REGISTRO = RAIZ / "plugins" / "registro.json"


def validar_registro(datos, fallos):
    """Treat registry entries as pull requests from strangers and validate them.

    Check here in CI rather than at installation: a broken entry merged into
    `main` reaches everyone searching, with failures on their machines.
    Manifests receive the same treatment.
    """
    entradas = datos.get("plugins")
    if not isinstance(entradas, list):
        fallos.append("the registry does not contain a plugin list")
        return
    vistos = set()
    for i, e in enumerate(entradas):
        donde = f"registro[{i}]"
        if not isinstance(e, dict):
            fallos.append(f"{donde}: not an object")
            continue
        ident = e.get("id")
        donde = f"registro/{ident}" if ident else donde
        if not isinstance(ident, str) or not RE_ID.fullmatch(ident):
            fallos.append(f"{donde}: missing or malformed id")
        elif ident in vistos:
            fallos.append(f"{donde}: duplicate id")
        else:
            vistos.add(ident)
        for campo in ("title", "description", "repo"):
            if not isinstance(e.get(campo), str) or not e[campo].strip():
                fallos.append(f"{donde}: missing {campo}")
        repo = str(e.get("repo") or "")
        if repo and not repo.startswith(("https://", "http://")):
            fallos.append(f"{donde}: repo must be an http(s) URL")
        #  Commit remains optional DURING the transition, but when present
        #  must be a full SHA: a partial pin is not a pin.
        sha = e.get("commit")
        if sha is not None and (not isinstance(sha, str)
                                or not RE_SHA.fullmatch(sha)):
            fallos.append(f"{donde}: commit must be a 40-character lowercase "
                          "SHA")
        carpeta = _campo(e, "folder", "carpeta")
        if carpeta is not None:
            c = str(carpeta)
            if c.startswith("/") or ".." in c.split("/"):
                fallos.append(f"{donde}: folder must be relative and contain no ..")


#  ── communicating with the bar ──────────────────────────────────────
#
#  The same commands, responding in JSON. Deliberately not a separate script:
#  two installation paths would diverge, with bugs hiding in the less-used
#  one. Share code and validation; only the response's audience changes.
#
#  One flushed line per event, like the editor: the bar needs to show
#  "cloning..." while cloning, not a wall of text when it finishes.

def _decir(**d):
    print(json.dumps(d, ensure_ascii=False), flush=True)


def json_examinar(url, subcarpeta=None, commit=None):
    """Fetch, examine, and describe a plugin WITHOUT installing it.

    This supplies the first half of the bar's permissions dialog. Return the
    examined commit for the bar to pass later as `--commit`, ensuring the
    installation matches what was shown even if the branch moves while the
    user reads the dialog.
    """
    with _traer(url, subcarpeta, commit) as t:
        if not t.ok:
            _decir(ok=False, motivo=t.motivo, detalle=t.detalle,
                   commit=t.commit)
            return 1
        i = t.item
        anterior = leer_origen(i["id"]) or {}
        _decir(ok=True,
               reglas=revisar_reglas(t.carpeta),
               plugin={
                   "id": i["id"],
                   "title": i.get("title", i["id"]),
                   "version": i.get("version", "0"),
                   "description": i.get("description", ""),
                   "permissions": i.get("permissions") or [],
                   "surfaces": i.get("surfaces") or [],
                   "host": i.get("host", ""),
               },
               repo=url,
               carpeta=subcarpeta or "",
               commit=t.commit,
               anclado=bool(commit),
               reemplaza=(DE_USUARIO / i["id"]).is_dir(),
               commitAnterior=anterior.get("commit", ""))
    return 0


def json_buscar(url=None):
    """Return registry data for the bar to display."""
    try:
        datos = leer_registro(url)
    except Exception as exc:
        _decir(ok=False, motivo="sin-registro", detalle=str(exc))
        return 2
    fallos_reg = []
    validar_registro(datos, fallos_reg)
    #  Serve a registry with broken entries after excluding those entries:
    #  a malformed PR must not leave the entire store blank.
    malas = {f.split("/", 1)[1].split(":")[0] for f in fallos_reg if "/" in f}
    entradas = [e for e in datos.get("plugins") or []
                if str(e.get("id")) not in malas]
    instalado = {}
    for d in (DE_USUARIO.iterdir() if DE_USUARIO.is_dir() else []):
        if d.is_dir():
            o = leer_origen(d.name) or {}
            instalado[d.name] = o.get("commit", "")
    for e in entradas:
        i = str(e.get("id"))
        e["instalado"] = i in instalado
        e["alDia"] = bool(e.get("commit")) and instalado.get(i) == e["commit"]
    _decir(ok=True, plugins=entradas, descartadas=sorted(malas))
    return 0


def json_instalados():
    ids_repo, version_host = _contexto()
    fuera = []
    for item in cargar_usuario(ids_repo, version_host):
        o = leer_origen(item["id"]) or {}
        fuera.append({
            "id": item["id"],
            "version": item.get("version", "0"),
            "title": item.get("title", item["id"]),
            "cargable": bool(item.get("cargable")),
            "motivo": item.get("motivo", ""),
            "detalle": item.get("detalle", ""),
            "dice": item.get("dice", ""),
            "permissions": item.get("permissions") or [],
            "repo": o.get("repo", ""),
            "folder": o.get("folder", ""),
            "commit": o.get("commit", ""),
            "cuando": o.get("cuando", 0),
        })
    _decir(ok=True, plugins=fuera)
    return 0


def json_comprobar(url=None):
    ids_repo, version_host = _contexto()
    try:
        datos = leer_registro(url)
    except Exception as exc:
        _decir(ok=False, motivo="sin-registro", detalle=str(exc))
        return 2
    publicado = {str(e.get("id")): e for e in datos.get("plugins") or []}
    fuera = []
    for item in cargar_usuario(ids_repo, version_host):
        ident = item["id"]
        mio = str((leer_origen(ident) or {}).get("commit") or "")
        e = publicado.get(ident)
        suyo = str((e or {}).get("commit") or "")
        if not e:
            estado = "fuera-del-registro"
        elif not mio:
            estado = "sin-anclar"
        elif not suyo:
            estado = "registro-sin-commit"
        elif suyo == mio:
            estado = "al-dia"
        else:
            estado = "novedad"
        fuera.append({"id": ident, "estado": estado,
                      "mio": mio, "suyo": suyo})
    _decir(ok=True, plugins=fuera)
    return 0


def comprobar(url=None):
    """Report installed plugins that differ from the registry.

    Previously only the source was known, not the exact version, so "am I
    up to date?" and "has the code changed underneath me?" could not be
    distinguished.
    """
    ids_repo, version_host = _contexto()
    externos = cargar_usuario(ids_repo, version_host)
    if not externos:
        print("no user plugins installed.")
        return 0
    try:
        datos = leer_registro(url)
    except Exception as exc:
        print(f"could not read the registry: {exc}", file=sys.stderr)
        return 2
    publicado = {str(e.get("id")): e for e in datos.get("plugins") or []}

    novedades = 0
    for item in externos:
        ident = item["id"]
        o = leer_origen(ident) or {}
        mio = str(o.get("commit") or "")
        e = publicado.get(ident)
        if not e:
            que = "not in the registry (installed manually)"
        elif not mio:
            que = "unknown commit (installed with an older version)"
        elif not e.get("commit"):
            que = "the registry has no commit to compare"
        elif str(e["commit"]) == mio:
            que = f"up to date  ·  {mio[:12]}"
        else:
            que = f"update available  ·  {mio[:12]} → {str(e['commit'])[:12]}"
            novedades += 1
        print(f"{ident:<16} {que}")

    if novedades:
        print(f"\n{novedades} with updates available. To fetch an update:"
              " tools/plugins.py --update <id> --commit <sha>")
    return 0


def main():
    fallos: list[str] = []
    try:
        datos, plugins = leer_catalogo()
    except Exception as exc:
        print(f"unreadable catalog: {exc}", file=sys.stderr)
        return 2

    ids = validar_repo(plugins, fallos)

    #  Check the storefront too, if present: it belongs to the repo and can break.
    if FICHERO_REGISTRO.is_file():
        try:
            validar_registro(json.loads(FICHERO_REGISTRO.read_text()), fallos)
        except Exception as exc:
            fallos.append(f"registro.json unreadable: {exc}")

    if fallos:
        print("The plugin catalog has problems:\n")
        print("\n".join("  - " + x for x in fallos))
        return 1

    version_host = str(datos.get("version", "1.0.0"))

    #  Use the same collision check as `listar()` so terminal validation
    #  reports conflicts before a plugin stops responding.
    for item in plugins:
        entrada = item.get("entry")
        if not entrada:
            continue
        carpeta = (RAIZ / "plugins" / entrada).parent
        if carpeta.is_dir():
            item["comandos"] = comandos_de_carpeta(carpeta)

    externos = cargar_usuario(ids, version_host)
    marcar_choques(list(plugins) + externos)
    rotos = [e for e in externos if not e.get("cargable")]
    print(f"{len(plugins)} repository plugins verified"
          + (f" · {len(externos)} user plugins" if externos else "")
          + (f" ({len(rotos)} unloadable)" if rotos else "") + ".")
    for e in rotos:
        print(f"  - {e['id']}: {e.get('dice') or e.get('motivo')}")
    return 0


AYUDA = """k4's plugin catalog.

    tools/plugins.py                    validate the repo and what's installed
    tools/plugins.py --new <id>         create one that already runs
    tools/plugins.py --test <id>        open it on its own, without touching your bar
    tools/plugins.py --list             emit the combined catalog (JSON)
    tools/plugins.py --installed        what you have from outside
    tools/plugins.py --install <url>    clone, validate, ask, install
    tools/plugins.py --update <id>      reinstall from where it came
    tools/plugins.py --check            what you have that the registry has moved past
    tools/plugins.py --remove <id>      uninstall
    tools/plugins.py --search [text]    what's published in the registry
    tools/plugins.py --examine <url>    look at a plugin without installing it (JSON)

    --pantalla <m>  with --test, open it on THAT monitor (`hyprctl monitors`)
    --commit <sha>  install or update THAT commit, not the tip of the branch
    --folder <dir>  when plugin.json is not at the repo root
    --registry <url>  point at a registry other than the published one
    --json          answer in JSON, for the bar
    --yes           don't ask (for scripts)
    --with-state    when removing, also delete what the plugin saved
    --help          this

The Spanish flags this started with —--instalar, --probar, --nuevo…— still
work and are not going away. The code speaks Spanish; the door doesn't have
to.
"""


#  ── create a plugin and test it without risking the desktop ──────────
#
#  The two things most needed when writing a first plugin. Good documentation
#  may span five hundred lines, but the first hour calls for something that
#  runs. Testing in YOUR bar, which holds your clipboard and session, means
#  an infinite loop can freeze the desktop.

PLANTILLA_MANIFIESTO = """{
  "id": "%(id)s",
  "entry": "%(clase)sPlugin.qml",
  "version": "0.1.0",
  "title": "%(titulo)s",
  "description": "A freshly born plugin",
  "host": ">=1.1.0",
  "permissions": [],
  "surfaces": ["island"]
}
"""

PLANTILLA_QML = """//  %(titulo)s
//
//  A k4 plugin is an object with a name and a view. The host creates it ONCE
//  and keeps it alive; only the view appears and disappears. State belongs
//  here so it survives closing the view.
//
//  To test it without touching your bar:
//
//      tools/plugins.py --test %(id)s

import QtQuick
import K4 as K4

K4.Plugin {
    id: raiz

    name: "%(id)s"
    title: "%(titulo)s"

    //  Space requested in the island.
    islandWidth: 320
    islandHeight: 120

    //  The host opens and closes it through these methods.
    property bool abierto: false
    active: abierto
    function toggle() { abierto = !abierto }
    //  Without `close()`, Escape does nothing: the host calls it to close.
    function close() { abierto = false }

    view: Component {
        Item {
            K4.Etiqueta {
                anchors.centerIn: parent
                text: "Hello from %(titulo)s"
                font.pixelSize: 16
            }
        }
    }
}
"""


def nuevo(ident):
    """Create a working plugin instead of starting from an empty folder."""
    if not re.match(r"^[a-z][a-z0-9-]*$", ident or ""):
        print("An id uses lowercase letters, numbers, and hyphens: my-plugin")
        return 2
    destino = DE_USUARIO / ident
    if destino.exists():
        print("Already exists: %s" % destino)
        return 1
    clase = "".join(p.capitalize() for p in ident.split("-"))
    datos = {"id": ident, "titulo": clase, "clase": clase}
    destino.mkdir(parents=True)
    (destino / "plugin.json").write_text(PLANTILLA_MANIFIESTO % datos)
    (destino / (clase + "Plugin.qml")).write_text(PLANTILLA_QML % datos)
    print("Created: %s" % destino)
    print()
    print("  tools/plugins.py --test %s    opens it without touching your bar" % ident)
    print("  tools/plugins.py                 validates it")
    print("  quickshell ipc -p shell.qml call k4 pluginEnable %s" % ident)
    return 0


BANCO = """//  Plugin test bench, generated by `tools/plugins.py --test`.
//
//  Loads ONE plugin only: no bar, services, or personal notifications.
//  If the plugin hangs, this instance hangs rather than your desktop.
//
//  Deliberately placed at the k4 root: Quickshell cannot load files outside
//  the configuration folder, so a test bench in /tmp could not open the
//  plugin.

import QtQuick
import Quickshell
import Quickshell.Wayland
import K4 as K4

ShellRoot {
    id: banco

    property var plugin: null

    Component.onCompleted: {
        const c = Qt.createComponent("%(entry)s")
        if (c.status === Component.Error) {
            console.log("TEST BENCH failed to load:\\n" + c.errorString())
            return
        }
        banco.plugin = c.createObject(null, {
            habilitado: true,
            carpeta: Quickshell.shellPath("%(carpeta)s")
        })
        if (banco.plugin && typeof banco.plugin.toggle === "function")
            banco.plugin.toggle()
        console.log("TEST BENCH ready:", banco.plugin ? banco.plugin.name : "none")
    }

    PanelWindow {
        visible: banco.plugin !== null

        //  Choose the monitor. Empty lets the compositor decide as usual;
        //  `--pantalla` selects a specific output, allowing testing on a
        //  second monitor while using the first, a basic test-bench need.
        screen: {
            const quiere = "%(pantalla)s"
            if (quiere.length === 0)
                return null
            const lista = Quickshell.screens
            for (let i = 0; i < lista.length; ++i)
                if (lista[i].name === quiere)
                    return lista[i]
            console.log("TEST BENCH: no screen named «" + quiere + "»")
            return null
        }

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "k4-banco"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore

        Rectangle {
            anchors.fill: parent
            color: "#cc000000"
            MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
        }

        Rectangle {
            anchors.centerIn: parent
            width: banco.plugin ? banco.plugin.islandWidth : 320
            height: banco.plugin ? banco.plugin.islandHeight : 120
            radius: 14
            color: "#1c1c1e"
            border.width: 1
            border.color: "#3a3a3c"
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: banco.plugin ? banco.plugin.view : null
            }
        }

        //  A reminder: it is easy to forget that this is not the live bar.
        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            text: "test bench · click outside to exit"
            color: "#8e8e93"
            font.pixelSize: 12
        }
    }
}
"""


def probar(ident, pantalla=""):
    """Open ONE plugin in a separate instance without touching the live bar."""
    #  `leer_catalogo` returns (metadata, list); only the list matters here.
    catalogo = {m.get("id"): m for m in leer_catalogo()[1]}
    if ident in catalogo:
        entry = "plugins/" + catalogo[ident]["entry"]
    else:
        manif = DE_USUARIO / ident / "plugin.json"
        if not manif.exists():
            print("Cannot find plugin «%s»." % ident)
            return 1
        try:
            m = json.loads(manif.read_text(encoding="utf-8"))
        except ValueError as e:
            print("Its plugin.json is unreadable: %s" % e)
            return 1
        entry = "externos/%s/%s" % (ident, m.get("entry", ""))

    if not (RAIZ / entry).exists():
        print("Entry is missing from the manifest's declared location: %s" % entry)
        return 1

    banco = RAIZ / ".banco.qml"
    banco.write_text(BANCO % {"entry": entry,
                              "carpeta": str(pathlib.PurePosixPath(entry).parent),
                              "pantalla": pantalla})

    entorno = dict(os.environ)
    api = str(RAIZ / "api")
    entorno["QML_IMPORT_PATH"] = (api + ":" + entorno["QML_IMPORT_PATH"]
                                  if entorno.get("QML_IMPORT_PATH") else api)
    print("Opening «%s» in a separate test bench. Click outside to exit." % ident)
    try:
        return subprocess.call(["quickshell", "-p", str(banco)], env=entorno)
    except KeyboardInterrupt:
        return 0
    finally:
        try:
            banco.unlink()
        except OSError:
            pass


def _valor(bandera):
    if bandera in sys.argv:
        i = sys.argv.index(bandera)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


#  Flags are written in English; legacy flags remain supported.
#
#  Internal identifiers originated in Spanish, but CLI flags are the public
#  entry point. Plugin users may not understand `probar`; language should not
#  restrict participation. The publication form is English for the same reason.
#
#  Spanish flags remain without deprecation warnings: they appear in README
#  examples, users' scripts, and established habits. Compatibility costs one
#  dictionary.
EN_ESPANOL = {
    "--install": "--instalar",
    "--test": "--probar",
    "--new": "--nuevo",
    "--check": "--comprobar",
    "--search": "--buscar",
    "--remove": "--quitar",
    "--update": "--actualizar",
    "--examine": "--examinar",
    "--list": "--listar",
    "--installed": "--instalados",
    "--reload": "--recargar",
    "--yes": "--si",
    "--folder": "--carpeta",
    "--registry": "--registro",
    "--with-state": "--con-estado",
}


def traducir_banderas(argv):
    """Translate English flags to their internal equivalents."""
    return [EN_ESPANOL.get(a, a) for a in argv]


if __name__ == "__main__":
    #  Normalize first so the rest of the script handles one set of names
    #  rather than remembering both spellings in every branch.
    sys.argv = traducir_banderas(sys.argv)

    #  Accept the conventional `--help` too. Previously it did not fail but
    #  fell through to full catalog validation, which was slow and unrelated
    #  to the user's request.
    if ("--ayuda" in sys.argv or "--help" in sys.argv or "-h" in sys.argv):
        print(AYUDA)
        sys.exit(0)
    _si = "--si" in sys.argv
    _commit = _valor("--commit")
    #  `--json` reuses the same commands with JSON responses, sparing the bar
    #  from parsing human-facing text.
    _json = "--json" in sys.argv
    if "--examinar" in sys.argv:
        _url = _valor("--examinar")
        sys.exit(json_examinar(_url, _valor("--carpeta"), _commit)
                 if _url else 2)
    if "--instalar" in sys.argv:
        _url = _valor("--instalar")
        if not _url:
            sys.exit(2)
        _r = instalar(_url, _si, _valor("--carpeta"), _commit)
        if _json:
            _decir(ok=_r == 0, id=_valor("--instalar"))
        sys.exit(_r)
    if "--actualizar" in sys.argv:
        _id = _valor("--actualizar")
        sys.exit(actualizar(_id, _si, _commit) if _id else 2)
    if "--comprobar" in sys.argv:
        _u = _valor("--registro")
        sys.exit(json_comprobar(_u) if _json else comprobar(_u))
    if "--quitar" in sys.argv:
        _id = _valor("--quitar")
        if not _id:
            sys.exit(2)
        _r = quitar(_id, _si, "--con-estado" in sys.argv)
        if _json:
            _decir(ok=_r == 0, id=_id)
        sys.exit(_r)
    if "--buscar" in sys.argv:
        _t = _valor("--buscar")
        if _json:
            sys.exit(json_buscar(_valor("--registro")))
        sys.exit(buscar(None if _t and _t.startswith("--") else _t,
                        _valor("--registro")))
    if "--nuevo" in sys.argv:
        _id = _valor("--nuevo")
        sys.exit(nuevo(_id) if _id else 2)
    if "--probar" in sys.argv:
        _id = _valor("--probar")
        sys.exit(probar(_id, _valor("--pantalla") or "") if _id else 2)
    if "--instalados" in sys.argv:
        sys.exit(json_instalados() if _json else instalados())
    if "--recargar" in sys.argv:
        i = sys.argv.index("--recargar")
        sys.exit(recargar(sys.argv[i + 1]) if i + 1 < len(sys.argv) else 2)
    sys.exit(listar() if "--listar" in sys.argv else main())
