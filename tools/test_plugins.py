#!/usr/bin/env python3
"""Tests for the plugin catalog: the script that installs THIRD-PARTY code.

    python3 tools/test_plugins.py

`plugins.py` is the entry point for external code: it validates manifests,
compares declared permissions against actual QML usage, and rejects invalid
plugins before modifying the installation.

Each test creates its plugin folder in temporary storage, independent of
plugins installed on the machine.
"""
import contextlib
import io
import json
import pathlib
import shutil
import subprocess
import struct
import sys
import tempfile
import zlib
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import plugins
import publish

fallos = []
BORRADOR = pathlib.Path(tempfile.mkdtemp(prefix="k4-prueba-plugins-"))
HOST = "1.1.0"


def igual(que, es, deberia):
    if es != deberia:
        fallos.append("%s\n    actual: %r\n  expected: %r" % (que, es, deberia))


def contiene(que, texto, trozo):
    if trozo not in str(texto):
        fallos.append("%s\n    actual: %r\n  should contain: %r"
                      % (que, texto, trozo))


def carpeta(nombre, manifiesto=None, ficheros=None):
    """Create a fresh plugin folder with the requested contents."""
    d = BORRADOR / nombre
    d.mkdir(parents=True, exist_ok=True)
    for viejo in d.iterdir():
        viejo.unlink()
    if manifiesto is not None:
        (d / "plugin.json").write_text(json.dumps(manifiesto))
    for ruta, contenido in (ficheros or {}).items():
        modo = "wb" if isinstance(contenido, bytes) else "w"
        with open(d / ruta, modo) as f:
            f.write(contenido)
    return d


def manifiesto_base(ident):
    return {"id": ident, "entry": "Plugin.qml", "version": "1.0.0",
            "title": ident, "description": "test", "host": ">=1.0.0",
            "permisos": []}


def png(ancho, alto):
    """A minimal PNG header: signature and IHDR with the requested dimensions."""
    ihdr = struct.pack(">IIBBBBB", ancho, alto, 8, 2, 0, 0, 0)
    trozo = b"IHDR" + ihdr
    return (b"\x89PNG\r\n\x1a\n"
            + struct.pack(">I", len(ihdr)) + trozo
            + struct.pack(">I", zlib.crc32(trozo)))


# ── pure functions ───────────────────────────────────────────────────

def prueba_version_tupla():
    igual("a normal version", plugins.version_tupla("1.2.3"), (1, 2, 3))
    igual("garbage returns None", plugins.version_tupla("uno.dos"), None)


def prueba_host_compatible():
    igual("no requirement is compatible", plugins.host_compatible(None, HOST), True)
    igual("newer satisfies", plugins.host_compatible(">=1.0.0", HOST), True)
    igual("equal satisfies", plugins.host_compatible(">=1.1.0", HOST), True)
    igual("older fails", plugins.host_compatible(">=2.0.0", HOST), False)
    igual("unsupported format fails", plugins.host_compatible("^1.0.0", HOST), False)


# ── folder validation ────────────────────────────────────────────────

def prueba_plugin_valido():
    d = carpeta("hola", manifiesto_base("hola"),
                {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("a valid plugin is loadable", v["cargable"], True)
    igual("entry is absolute", v["entry"], str(d / "Plugin.qml"))
    igual("qmldir is generated automatically", (d / "qmldir").is_file(), True)
    contiene("with its types listed", (d / "qmldir").read_text(), "Plugin 1.0")


def prueba_sin_manifiesto():
    d = carpeta("roto")
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("missing plugin.json prevents loading", v["cargable"], False)
    contiene("and is reported", v["dice"], "plugin.json")


def prueba_manifiesto_ilegible():
    d = carpeta("basura", ficheros={"plugin.json": "{this is not json"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("broken JSON prevents loading", v["cargable"], False)
    contiene("with an explanation", v["dice"], "unreadable")


def prueba_id_invalido():
    d = carpeta("malo", dict(manifiesto_base("malo"), id="Con Mayúsculas"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("an id with capitals and spaces is rejected", v["cargable"], False)


def prueba_id_no_coincide_con_carpeta():
    d = carpeta("una-cosa", manifiesto_base("otra-cosa"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("an id differing from the folder prevents loading", v["cargable"], False)
    contiene("both names are reported", v["dice"], "otra-cosa")


def prueba_id_del_repo_gana():
    d = carpeta("game", manifiesto_base("game"), {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, {"game"}, HOST)
    igual("cannot impersonate a bundled plugin", v["cargable"], False)


def prueba_id_nativo_reservado():
    for ident in ["idle", "volume", "sound", "clock", "player", "toast",
                  "panel", "session", "tray"]:
        d = carpeta(ident, manifiesto_base(ident),
                    {"Plugin.qml": "Item {}\n"})
        v = plugins.validar_carpeta(d, set(), HOST)
        igual("native id %s cannot be claimed" % ident,
              v["cargable"], False)
        igual("with its reason code", v["motivo"], "id-nativo")


def prueba_comando_nativo_reservado():
    d = carpeta("mezclador", manifiesto_base("mezclador"),
                {"Plugin.qml": 'Item { K4.Ipc { target: "k4.sound" } }\n'})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("native commands cannot be claimed", v["cargable"], False)
    igual("with its reason code", v["motivo"], "comando-nativo")


def prueba_entry_con_ruta():
    d = carpeta("listillo", dict(manifiesto_base("listillo"),
                                 entry="../fuera.qml"))
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("an entry with parent traversal prevents loading", v["cargable"], False)


def prueba_entry_inexistente():
    d = carpeta("vacio", manifiesto_base("vacio"))
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("missing entry file prevents loading", v["cargable"], False)


def prueba_host_viejo():
    d = carpeta("futuro", dict(manifiesto_base("futuro"), host=">=9.0.0"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("requiring a future bar version prevents loading", v["cargable"], False)


# ── permissions: the core validation boundary ─────────────────────────

def prueba_permiso_desconocido():
    d = carpeta("inventor", dict(manifiesto_base("inventor"),
                                 permisos=["superpoderes"]),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("an invented permission prevents loading", v["cargable"], False)
    contiene("and is named", v["dice"], "superpoderes")


def prueba_usa_sin_declarar():
    d = carpeta("colado", manifiesto_base("colado"),
                {"Plugin.qml": "Item { K4.Process { command: [\"ls\"] } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("undeclared K4.Process usage prevents loading", v["cargable"], False)
    #  The reason is a code for the bar's presentation layer. The missing
    #  permission is in `detalle`, with an English explanation in `dice` for
    #  terminal users.
    igual("with its reason code", v["motivo"], "sin-declarar")
    contiene("details identify the permission", v["detalle"], "procesos")
    contiene("the explanation remains available", v["dice"], "uses without declaring")


def prueba_usa_declarado():
    d = carpeta("honesto", dict(manifiesto_base("honesto"),
                                permisos=["procesos"]),
                {"Plugin.qml": "Item { K4.Process { command: [\"ls\"] } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("declared usage is loadable", v["cargable"], True)


def prueba_comentario_no_delata():
    d = carpeta("comentado", manifiesto_base("comentado"),
                {"Plugin.qml": "Item {} // someday I will use K4.Process\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("mentioning K4.Process in a comment is not usage",
          v["cargable"], True)


def prueba_portapapeles_delata_al_leer():
    d = carpeta("fisgon", manifiesto_base("fisgon"),
                {"Plugin.qml":
                 "Item { property var h: K4.Portapapeles.entradas }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("even READING the clipboard requires permission", v["cargable"], False)
    contiene("with its name", v["dice"], "portapapeles")


def prueba_la_vista_tambien_se_examina():
    d = carpeta("repartido", manifiesto_base("repartido"),
                {"Plugin.qml": "Item {}\n",
                 "Vista.qml": "Item { K4.Sonido { fuente: \"x.wav\" } }\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("permissions are checked in ALL .qml files, not just the entry",
          v["cargable"], False)


# ── icons ────────────────────────────────────────────────────────────

def prueba_icono_codice():
    d = carpeta("glifo", dict(manifiesto_base("glifo"), icono="0xF04E5"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("a code point is valid", v["cargable"], True)
    igual("and is recorded", v["icon"], "0xF04E5")
    igual("legacy icon input is not emitted", "icono" in v, False)


def prueba_icono_inexistente():
    d = carpeta("sin-icono", dict(manifiesto_base("sin-icono"),
                                  icono="nada.png"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("a nonexistent icon prevents loading", v["cargable"], False)


def prueba_icono_pequeno():
    d = carpeta("borroso", dict(manifiesto_base("borroso"), icono="i.png"),
                {"Plugin.qml": "Item {}\n", "i.png": png(32, 32)})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("a 32px PNG is below the minimum", v["cargable"], False)
    contiene("the reason explains it", v["dice"], "32x32")


def prueba_icono_decente():
    d = carpeta("nitido", dict(manifiesto_base("nitido"), icono="i.png"),
                {"Plugin.qml": "Item {}\n", "i.png": png(128, 128)})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("a 128px PNG loads", v["cargable"], True)
    contiene("with its absolute path", v["iconFile"], str(d / "i.png"))
    igual("legacy image output is absent", "iconoFichero" in v, False)


def prueba_icono_con_ruta():
    d = carpeta("ladron", dict(manifiesto_base("ladron"),
                               icono="../../otro.png"),
                {"Plugin.qml": "Item {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("an icon with a path is rejected", v["cargable"], False)


# ── registry entries submitted by strangers ───────────────────────────

def _reg(**e):
    """Return validation failures for a single registry entry."""
    base = {"id": "x", "title": "X", "description": "d",
            "repo": "https://ejemplo/repo"}
    base.update(e)
    fallos_reg = []
    plugins.validar_registro({"plugins": [base]}, fallos_reg)
    return fallos_reg


def prueba_registro_entrada_correcta():
    igual("a valid entry has no failures",
          _reg(commit="a" * 40, carpeta="ejemplos/x"), [])


def prueba_registro_commit_entero_o_ninguno():
    #  A partial pin is not a pin: short SHAs can be ambiguous, and uppercase
    #  SHAs do not match Git's output.
    igual("a short SHA is invalid", len(_reg(commit="abc123")), 1)
    igual("uppercase is invalid too", len(_reg(commit="A" * 40)), 1)
    igual("a branch is also invalid", len(_reg(commit="main")), 1)
    igual("missing commits are accepted during the transition",
          _reg(), [])


def prueba_registro_campos_y_forma():
    igual("title is required", len(_reg(title="")), 1)
    igual("description is required", len(_reg(description=None)), 1)
    igual("repo must be a URL", len(_reg(repo="git@github:a/b")), 1)
    igual("id must follow its format", len(_reg(id="Mal Id")), 1)


def prueba_registro_carpeta_no_se_escapa():
    #  The folder is appended to the temporary clone path. `..` could point
    #  outside it.
    igual("reject parent traversal", len(_reg(carpeta="../fuera")), 1)
    igual("reject absolute paths", len(_reg(carpeta="/etc")), 1)
    igual("a normal folder passes", _reg(carpeta="ejemplos/x"), [])


def prueba_registro_sin_ids_repetidos():
    fallos_reg = []
    plugins.validar_registro({"plugins": [
        {"id": "x", "title": "X", "description": "d", "repo": "https://a/b"},
        {"id": "x", "title": "Y", "description": "d", "repo": "https://a/c"},
    ]}, fallos_reg)
    igual("two entries with the same id", len(fallos_reg), 1)


def prueba_registro_de_verdad_es_valido():
    #  Check the published registry, not a fixture.
    if plugins.FICHERO_REGISTRO.is_file():
        fallos_reg = []
        plugins.validar_registro(
            json.loads(plugins.FICHERO_REGISTRO.read_text()), fallos_reg)
        igual("the published registry passes its own validator",
              fallos_reg, [])


# ── pinning: install ONE commit and record which one ──────────────────
#
#  These perform real installations, but NEVER in `~/.config/k4/plugins`:
#  redirect `plugins.DE_USUARIO` to temporary storage. Tests touching real
#  plugins could not safely run while the bar is open.

def _git(d, *args):
    subprocess.run(["git", "-C", str(d)] + list(args),
                   check=True, capture_output=True)


def repo_con_dos_commits(nombre="anclado", dentro=""):
    """Create a fixture Git repository containing two versions of a plugin.

    Return (path, old_sha, new_sha). The plugin version changes between the
    commits, identifying which one was actually installed.
    """
    d = BORRADOR / ("repo-" + nombre)
    if d.exists():
        shutil.rmtree(d)
    base = (d / dentro) if dentro else d
    base.mkdir(parents=True)
    _git_init = subprocess.run(["git", "init", "-q", "-b", "main", str(d)],
                               check=True, capture_output=True)
    _git(d, "config", "user.email", "prueba@k4")
    _git(d, "config", "user.name", "Test")

    man = manifiesto_base(nombre)
    (base / "plugin.json").write_text(json.dumps(man))
    (base / "Plugin.qml").write_text("import QtQuick\nItem {}\n")
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", "First version")
    viejo = subprocess.run(["git", "-C", str(d), "rev-parse", "HEAD"],
                           capture_output=True, text=True).stdout.strip()

    man["version"] = "2.0.0"
    (base / "plugin.json").write_text(json.dumps(man))
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", "Second version")
    nuevo = subprocess.run(["git", "-C", str(d), "rev-parse", "HEAD"],
                           capture_output=True, text=True).stdout.strip()
    return d, viejo, nuevo


class DestinoAparte:
    """Temporarily point `plugins.DE_USUARIO` at a fixture directory."""

    def __init__(self, nombre):
        self.d = BORRADOR / ("destino-" + nombre)

    def __enter__(self):
        if self.d.exists():
            shutil.rmtree(self.d)
        self.d.mkdir(parents=True)
        self.antes = plugins.DE_USUARIO
        plugins.DE_USUARIO = self.d
        #  Installation rightly prints permissions, destination, and the
        #  sandbox disclaimer. Multiple installations would drown the test
        #  summary, so capture the output for inspection if a test fails.
        self.dicho = io.StringIO()
        self.silencio = contextlib.redirect_stdout(self.dicho)
        self.silencio.__enter__()
        return self.d

    def __exit__(self, *_):
        self.silencio.__exit__(None, None, None)
        plugins.DE_USUARIO = self.antes
        return False


def arbol(d):
    """Return file paths and contents for comparing two installations."""
    fuera = {}
    for f in sorted(d.rglob("*")):
        if f.is_file():
            fuera[str(f.relative_to(d))] = f.read_bytes()
    return fuera


def prueba_ancla_instala_el_commit_pedido():
    repo, viejo, nuevo = repo_con_dos_commits("pedido")
    with DestinoAparte("pedido") as destino:
        igual("installation succeeds",
              plugins.instalar(str(repo), True, None, viejo), 0)
        o = json.loads((destino / "pedido" / plugins.ORIGEN).read_text())
        igual("records the requested commit", o["commit"], viejo)
        man = json.loads((destino / "pedido" / "plugin.json").read_text())
        igual("contents match THAT commit rather than the tip",
              man["version"], "1.0.0")


def prueba_ancla_sin_pedir_commit_va_a_la_punta():
    repo, viejo, nuevo = repo_con_dos_commits("punta")
    with DestinoAparte("punta") as destino:
        igual("installs", plugins.instalar(str(repo), True), 0)
        o = json.loads((destino / "punta" / plugins.ORIGEN).read_text())
        igual("records the tip", o["commit"], nuevo)
        igual("records the commit even without an explicit pin",
              plugins.RE_SHA.fullmatch(o["commit"]) is not None, True)


def prueba_ancla_actualizar_lleva_al_commit_dado():
    repo, viejo, nuevo = repo_con_dos_commits("subir")
    with DestinoAparte("subir") as destino:
        plugins.instalar(str(repo), True, None, viejo)
        igual("updates to the requested commit",
              plugins.actualizar("subir", True, nuevo), 0)
        o = json.loads((destino / "subir" / plugins.ORIGEN).read_text())
        igual("records that commit", o["commit"], nuevo)
        man = json.loads((destino / "subir" / "plugin.json").read_text())
        igual("with the new contents", man["version"], "2.0.0")


def prueba_ancla_actualizar_conserva_la_subcarpeta():
    #  Previously only the URL was saved, forcing updates to rediscover the
    #  plugin's repository subfolder. Two candidates made that impossible.
    repo, viejo, nuevo = repo_con_dos_commits("dentro", dentro="ejemplos/dentro")
    (repo / "otro").mkdir()
    (repo / "otro" / "plugin.json").write_text(
        json.dumps(manifiesto_base("otro")))
    (repo / "otro" / "Plugin.qml").write_text("import QtQuick\nItem {}\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "Add a second candidate")

    with DestinoAparte("dentro") as destino:
        igual("installs with an explicit folder",
              plugins.instalar(str(repo), True, "ejemplos/dentro"), 0)
        o = json.loads((destino / "dentro" / plugins.ORIGEN).read_text())
        igual("the folder is recorded", o["folder"], "ejemplos/dentro")
        igual("legacy folder output is absent", "carpeta" in o, False)
        igual("updates find the folder automatically",
              plugins.actualizar("dentro", True), 0)


def prueba_ancla_mismo_commit_mismo_arbol():
    repo, viejo, nuevo = repo_con_dos_commits("gemelo")
    with DestinoAparte("gemelo-a") as a:
        plugins.instalar(str(repo), True, None, viejo)
        uno = arbol(a / "gemelo")
    with DestinoAparte("gemelo-b") as b:
        plugins.instalar(str(repo), True, None, viejo)
        dos = arbol(b / "gemelo")
    #  Provenance contains a timestamp, so exclude it: the CODE must match.
    uno.pop(plugins.ORIGEN, None)
    dos.pop(plugins.ORIGEN, None)
    igual("the same commit produces the same tree twice", uno, dos)
    igual("the tree is not empty", len(uno) > 0, True)


def prueba_ancla_rechaza_un_commit_que_no_lo_es():
    repo, viejo, nuevo = repo_con_dos_commits("raro")
    with DestinoAparte("raro") as destino:
        igual("a branch is not a valid pin",
              plugins.instalar(str(repo), True, None, "main"), 1)
        igual("neither is a short SHA",
              plugins.instalar(str(repo), True, None, viejo[:8]), 1)
        igual("nothing was installed", list(destino.iterdir()), [])


def prueba_ancla_rechaza_un_commit_inexistente():
    repo, viejo, nuevo = repo_con_dos_commits("fantasma")
    with DestinoAparte("fantasma") as destino:
        igual("a commit absent from the repository is rejected",
              plugins.instalar(str(repo), True, None, "0" * 40), 1)
        igual("nothing was installed", list(destino.iterdir()), [])


def prueba_ancla_lee_el_origen_de_antes():
    #  Preserve older installations: their source is known even if their
    #  commit is not.
    with DestinoAparte("viejo") as destino:
        d = destino / "antiguo"
        d.mkdir()
        (d / ".origen").write_text("https://ejemplo/repo\n")
        o = plugins.leer_origen("antiguo")
        igual("reads the repository", o["repo"], "https://ejemplo/repo")
        igual("does not invent a commit", o.get("commit", ""), "")


# ── requests from the bar ─────────────────────────────────────────────

def dice(fn, *a, **k):
    """Return a JSON-mode command's response as an object."""
    salida = io.StringIO()
    with contextlib.redirect_stdout(salida):
        fn(*a, **k)
    return json.loads(salida.getvalue().strip().splitlines()[-1])


def prueba_json_examinar_no_instala_nada():
    #  Examination supplies the first half of the permissions dialog and must
    #  not change the installation. Installing here would make acceptance and
    #  cancellation equivalent, defeating consent.
    repo, viejo, nuevo = repo_con_dos_commits("examen")
    with DestinoAparte("examen") as destino:
        d = dice(plugins.json_examinar, str(repo), None, viejo)
        igual("reports success", d["ok"], True)
        igual("reports the examined commit", d["commit"], viejo)
        igual("includes manifest data", d["plugin"]["id"], "examen")
        igual("knows it is pinned", d["anclado"], True)
        igual("has NOT installed anything", list(destino.iterdir()), [])


def prueba_json_examinar_dice_por_que_no():
    repo, viejo, nuevo = repo_con_dos_commits("examen-malo")
    with DestinoAparte("examen-malo"):
        d = dice(plugins.json_examinar, str(repo), None, "0" * 40)
        igual("rejects the commit", d["ok"], False)
        #  A code rather than prose: the bar supplies the explanation.
        #  See `Motivos.porque()`.
        igual("identifies the problem", d["motivo"], "sin-commit")
        contiene("includes the commit in details", d["detalle"], "000000000000")


def prueba_json_examinar_avisa_de_que_reemplaza():
    repo, viejo, nuevo = repo_con_dos_commits("otra-vez")
    with DestinoAparte("otra-vez"):
        plugins.instalar(str(repo), True, None, viejo)
        d = dice(plugins.json_examinar, str(repo), None, nuevo)
        igual("reports an existing installation", d["reemplaza"], True)
        igual("reports its previous commit", d["commitAnterior"], viejo)


def prueba_json_buscar_marca_lo_que_tienes():
    repo, viejo, nuevo = repo_con_dos_commits("de-mentira-tienda")
    reg = BORRADOR / "registro-prueba.json"
    reg.write_text(json.dumps({"plugins": [
        {"id": "de-mentira-tienda", "title": "T", "description": "d",
         "repo": "https://ejemplo/t", "commit": viejo},
        {"id": "otro-que-no-tengo", "title": "O", "description": "d",
         "repo": "https://ejemplo/o", "commit": nuevo},
    ]}))
    with DestinoAparte("de-mentira-tienda"):
        plugins.instalar(str(repo), True, None, viejo)
        d = dice(plugins.json_buscar, reg.as_uri())
        por_id = {p["id"]: p for p in d["plugins"]}
        igual("identifies the installed plugin", por_id["de-mentira-tienda"]["instalado"], True)
        igual("knows it is up to date", por_id["de-mentira-tienda"]["alDia"], True)
        igual("identifies the uninstalled plugin",
              por_id["otro-que-no-tengo"]["instalado"], False)


def prueba_json_buscar_descarta_lo_roto():
    #  A malformed entry in a PR must not leave the store blank.
    reg = BORRADOR / "registro-roto.json"
    reg.write_text(json.dumps({"plugins": [
        {"id": "bueno", "title": "B", "description": "d",
         "repo": "https://ejemplo/b"},
        {"id": "malo", "title": "M", "description": "d",
         "repo": "https://ejemplo/m", "commit": "corto"},
    ]}))
    with DestinoAparte("roto"):
        d = dice(plugins.json_buscar, reg.as_uri())
        igual("serves valid entries", [p["id"] for p in d["plugins"]], ["bueno"])
        igual("reports discarded entries", d["descartadas"], ["malo"])


def prueba_search_folder_compatibility():
    #  Exercise the public CLI against real registry JSON. The old consumer
    #  tested the normalized folder, then indexed the missing legacy key.
    for fields, expected in [
        ({"folder": "examples/current"}, "examples/current"),
        ({"carpeta": "examples/legacy"}, "examples/legacy"),
        ({"folder": "examples/current", "carpeta": "examples/legacy"},
         "examples/current"),
        ({"folder": "", "carpeta": "examples/legacy"}, ""),
    ]:
        reg = BORRADOR / "search-folder.json"
        reg.write_text(json.dumps({"plugins": [{
            "id": "folder-search", "title": "Folder search", "description": "Test",
            "repo": "https://example.test/plugin", "commit": "a" * 40,
            **fields,
        }]}))
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(plugins.__file__)),
             "--search", "folder-search", "--registry", reg.as_uri()],
            capture_output=True, text=True, timeout=30)
        igual("folder search succeeds for %r: %s" % (fields, result.stderr),
              result.returncode, 0)
        command = "    install: tools/plugins.py --install https://example.test/plugin"
        if expected:
            command += " --folder " + expected
        command += " --commit " + "a" * 40
        commands = [line for line in result.stdout.splitlines()
                    if line.startswith("    install:")]
        igual("search prints the normalized, pinned install command", commands,
              [command])


def prueba_superficies_llegan_al_resultado():
    #  Surfaces used to be validated then discarded: manifests declared
    #  `island` but the store received an empty list. Users must SEE surfaces
    #  before enabling the plugin, so they must reach the result.
    d = carpeta("con-superficie",
                dict(manifiesto_base("con-superficie"), superficies=["island"]),
                {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v = plugins.validar_carpeta(d, set(), HOST)
    igual("loads", v["cargable"], True)
    igual("surfaces reach the result", v.get("surfaces"), ["island"])
    igual("legacy surface input is not emitted", "superficies" in v, False)

    #  Do not invent surfaces when none are declared.
    d2 = carpeta("sin-superficie", manifiesto_base("sin-superficie"),
                 {"Plugin.qml": "import QtQuick\nItem {}\n"})
    v2 = plugins.validar_carpeta(d2, set(), HOST)
    igual("undeclared surfaces remain absent", v2.get("surfaces"), None)


# ── named rules ──────────────────────────────────────────────────────

def con_ficheros(nombre, ficheros):
    d = BORRADOR / ("reglas-" + nombre)
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    for ruta, contenido in ficheros.items():
        f = d / ruta
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(contenido)
    return d


def ids_de(d):
    return sorted(r["id"] for r in plugins.revisar_reglas(d))


def prueba_reglas_descarga_y_ejecuta():
    d = con_ficheros("curl", {
        "i.sh": "#!/bin/sh\ncurl -sL https://x/y.sh | sh\n"})
    igual("curl piped to a shell", ids_de(d), ["descarga-y-ejecuta"])
    d = con_ficheros("curl2", {
        "i.sh": "wget -qO- https://x/y | sudo bash\n"})
    igual("also with wget and sudo", ids_de(d), ["descarga-y-ejecuta"])
    d = con_ficheros("curl-ok", {
        "i.sh": "curl -sL https://x/datos.json -o datos.json\n"})
    igual("downloading a file alone does not trigger it", ids_de(d), [])


def prueba_reglas_sudo_sin_contrasena():
    d = con_ficheros("sudo", {"i.sh": "sudo -n systemctl restart x\n"})
    igual("sudo -n", ids_de(d), ["sudo-sin-contrasena"])
    d = con_ficheros("nopass", {"i.sh": "# NOPASSWD: /usr/bin/x\n"})
    igual("NOPASSWD", ids_de(d), ["sudo-sin-contrasena"])


def prueba_reglas_qml_desde_texto():
    d = con_ficheros("qml", {
        "V.qml": "import QtQuick\nItem { function f(t) "
                 "{ return Qt.createQmlObject(t, this) } }\n"})
    igual("QML from a string", ids_de(d), ["qml-desde-texto"])


def prueba_reglas_no_miran_la_documentacion():
    #  A README example of `curl | sh` is not plugin behavior.
    d = con_ficheros("doc", {
        "LEEME.md": "Install it like this: curl -sL https://x/y | sh\n"})
    igual("documentation does not count", ids_de(d), [])


def prueba_reglas_solo_dos_bloquean():
    #  Only unequivocal violations block publication. Other findings flag the
    #  submission for human review rather than rejecting it.
    igual("blocking rules",
          sorted(r["id"] for r in plugins.REGLAS if r["bloquea"]),
          ["descarga-y-ejecuta", "sudo-sin-contrasena"])


def prueba_reglas_dicen_como_arreglarse():
    #  Warnings without actionable fixes get ignored and serve no purpose.
    for r in plugins.REGLAS:
        igual("%s explains why" % r["id"], len(r["porque"]) > 30, True)
        igual("%s explains how to fix it" % r["id"], len(r["arreglo"]) >= 1, True)


def prueba_reglas_no_saltan_con_los_plugins_de_casa():
    #  Bundled plugins are the reference: if a rule fires there, either the
    #  plugin is wrong or the rule is too broad.
    saltan = []
    for d in sorted((plugins.RAIZ / "plugins").iterdir()):
        if d.is_dir():
            for r in plugins.revisar_reglas(d):
                if r["bloquea"]:
                    saltan.append("%s: %s" % (d.name, r["donde"]))
    igual("no blocking findings in bundled plugins", saltan, [])


# ── flags in both languages ──────────────────────────────────────────

def prueba_banderas_en_ingles():
    #  The public entry point is English because users need not know Spanish.
    #  Internal identifiers can retain their original spelling independently
    #  of the flags exposed to users.
    igual("--install maps to --instalar",
          plugins.traducir_banderas(["x", "--install", "u"]),
          ["x", "--instalar", "u"])
    igual("--test maps to --probar",
          plugins.traducir_banderas(["x", "--test", "id"]),
          ["x", "--probar", "id"])


def prueba_banderas_en_espanol_siguen_valiendo():
    #  Legacy flags appear in the README, users' scripts, and established
    #  habits. Removing them would cost more than it saves.
    for vieja in ("--instalar", "--probar", "--nuevo", "--comprobar",
                  "--buscar", "--quitar", "--actualizar", "--examinar",
                  "--listar", "--instalados", "--si", "--carpeta"):
        igual("%s remains unchanged" % vieja,
              plugins.traducir_banderas(["x", vieja]), ["x", vieja])


def prueba_ninguna_bandera_se_come_a_otra():
    #  Replacing `--instalar` before `--instalados` could produce `--installdos`.
    #  Translating whole arguments rather than text prevents this classic
    #  substring-replacement bug.
    igual("--installed is not split into --install + dos",
          plugins.traducir_banderas(["x", "--installed"]), ["x", "--instalados"])
    igual("unknown arguments remain unchanged",
          plugins.traducir_banderas(["x", "--inventada", "--commit", "abc"]),
          ["x", "--inventada", "--commit", "abc"])


# ── publication workflow ─────────────────────────────────────────────
#
#  This admits strangers' code into the registry, so tests focus on what it
#  must REJECT.

def formulario(repo="https://github.com/quien/que",
               commit="a" * 40, carpeta="_No response_"):
    #  Legacy form labels are compatibility inputs, not generated UI prose.
    return ("### Repositorio\n\n%s\n\n### Commit\n\n%s\n\n"
            "### Carpeta\n\n%s\n" % (repo, commit, carpeta))


def prueba_publicar_lee_el_formulario_en_ingles():
    #  The current form is English for external contributors, but old Spanish
    #  labels remain valid: existing submissions must survive template changes.
    cuerpo = ("### Repository\n\nhttps://github.com/quien/que\n\n"
              "### Commit\n\n%s\n\n### Folder\n\nexamples/x\n" % ("a" * 40))
    d, malos = publish.envio(cuerpo)
    igual("no validation errors", malos, [])
    igual("repository", d["repo"], "https://github.com/quien/que")
    igual("folder", d["carpeta"], "examples/x")


def prueba_publicar_lee_el_formulario():
    d, malos = publish.envio(formulario(carpeta="ejemplos/x"))
    igual("no validation errors", malos, [])
    igual("repository", d["repo"], "https://github.com/quien/que")
    igual("commit", d["commit"], "a" * 40)
    igual("folder", d["carpeta"], "ejemplos/x")


def prueba_publicar_carpeta_vacia_es_vacia():
    #  GitHub writes "_No response_" for empty optional fields. Treating it as
    #  a folder would search for a plugin with that literal name.
    d, malos = publish.envio(formulario())
    igual("GitHub's placeholder is removed", d["carpeta"], "")


def prueba_publicar_exige_un_commit_de_verdad():
    for malo in ("main", "HEAD", "a" * 39, "a" * 41, "z" * 40, ""):
        d, malos = publish.envio(formulario(commit=malo))
        igual("rejects commit %r" % malo, len(malos) >= 1, True)


def prueba_publicar_normaliza_el_commit():
    #  An uppercase SHA identifies the SAME commit. Accept and lowercase it:
    #  the registry stores a single format, and comparison must not depend on
    #  how the author pasted it.
    d, malos = publish.envio(formulario(commit="A" * 40))
    igual("accepted", malos, [])
    igual("normalized to lowercase", d["commit"], "a" * 40)


def prueba_publicar_exige_un_repo_de_github():
    for malo in ("git@github.com:a/b.git", "https://gitlab.com/a/b",
                 "https://github.com/a/b/c", "ftp://github.com/a/b"):
        d, malos = publish.envio(formulario(repo=malo))
        igual("rejects repository %r" % malo, len(malos) >= 1, True)
    d, malos = publish.envio(formulario(repo="https://github.com/a/b/"))
    igual("trailing slash is removed", d["repo"], "https://github.com/a/b")


def prueba_publicar_carpeta_no_se_escapa():
    d, malos = publish.envio(formulario(carpeta="../../etc"))
    igual("rejects parent traversal", len(malos), 1)
    d, malos = publish.envio(formulario(carpeta="/etc"))
    igual("rejects absolute paths", len(malos), 1)


def prueba_publicar_no_firma_otro_commit():
    #  Review and approval must refer to the same commit. A changed commit
    #  must stop publication; otherwise approval would cover whatever the
    #  repository contains later, a promise nobody can make.
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    res = {"ok": True, "commit": "b" * 40,
           "plugin": {"id": "x", "title": "X", "description": "d"}}
    igual("does not publish a commit different from the reviewed one",
          publish.anadir(d, res), 1)


def prueba_publicar_marca_para_revision_si_pide_permisos():
    #  Keep legacy result inputs covered alongside the real English producer
    #  output exercised below.
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    limpio = {"ok": True, "commit": "a" * 40,
              "plugin": {"id": "sin-permisos", "title": "X",
                         "description": "d", "permisos": []}}
    _, etiqueta = publish.informe(d, [], limpio)
    igual("no permissions means validated", etiqueta, "validado")

    pide = {"ok": True, "commit": "a" * 40,
            "plugin": {"id": "con-permisos", "title": "X",
                       "description": "d", "permisos": ["procesos"]}}
    _, etiqueta = publish.informe(d, [], pide)
    igual("requesting permissions requires human review",
          etiqueta, "revision-de-seguridad")


def prueba_publication_consumes_real_examination():
    #  Use the real --examine subprocess, including cloning, pinning,
    #  validation, and JSON serialization. Handwritten legacy results hid the
    #  producer/consumer mismatch in the original publication tests.
    registry = BORRADOR / "publication-registry.json"
    registry.write_text(json.dumps({"plugins": []}))
    for vocabulary in ("english", "legacy", "both"):
        ident = "publication-" + vocabulary
        repo, _, _ = repo_con_dos_commits(ident)
        manifest = manifiesto_base(ident)
        manifest.pop("permisos")
        if vocabulary in ("english", "both"):
            manifest.update(permissions=["procesos"], surfaces=["island", "ipc"])
        if vocabulary in ("legacy", "both"):
            #  Conflicting aliases verify that English takes precedence.
            manifest.update(
                permisos=["procesos"] if vocabulary == "legacy" else [],
                superficies=["island", "ipc"] if vocabulary == "legacy" else [])
        (repo / "plugin.json").write_text(json.dumps(manifest))
        (repo / "Plugin.qml").write_text(
            'import QtQuick\nimport K4 as K4\nK4.Plugin {\n'
            '    name: "' + ident + '"\n'
            '    K4.Process { command: ["true"] }\n'
            '    K4.Ipc { target: "k4.' + ident + '" }\n'
            '    view: Component { Item {} }\n}\n')
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", "Declare permissions and surfaces")
        commit = plugins._commit_de(repo)
        submission = {"repo": str(repo), "commit": commit, "carpeta": ""}
        with DestinoAparte(ident) as destination, \
                mock.patch.dict("os.environ", {"HOME": str(destination)}), \
                mock.patch.object(publish, "REGISTRO", registry):
            result = publish.examinar(submission)
            igual("real examination succeeds for " + vocabulary, result["ok"], True)
            igual("examination returns the pinned commit", result["commit"], commit)
            igual("examination emits canonical manifest fields", result["plugin"], {
                "id": ident, "title": ident, "version": "1.0.0",
                "description": "test", "permissions": ["procesos"],
                "surfaces": ["ipc", "island"], "host": ">=1.0.0",
            })
            igual("no unrelated rule triggers review", result["reglas"], [])
            report, label = publish.informe(submission, [], result)
            igual("real permissions require human review", label, "revision-de-seguridad")
            contiene("report displays real permissions", report,
                     "| Permissions | `procesos` |")
            contiene("report displays real surfaces", report,
                     "| Surfaces | `ipc`, `island` |")
            igual("examination installs nothing", list(destination.iterdir()), [])


def prueba_publication_english_fields_override_legacy():
    submission = {"repo": "https://github.com/example/plugin",
                  "commit": "a" * 40, "carpeta": ""}
    result = {"ok": True, "plugin": {
        "id": "publication-precedence", "permissions": [], "surfaces": [],
        "permisos": ["procesos"], "superficies": ["island"],
    }}
    with mock.patch.object(publish, "REGISTRO", BORRADOR / "absent-registry.json"):
        report, label = publish.informe(submission, [], result)
    igual("explicit English empty permissions win", label, "validado")
    contiene("report uses English permissions", report, "| Permissions | none |")
    contiene("report uses English surfaces", report, "| Surfaces | undeclared |")


def prueba_publicar_dice_que_no_es_una_auditoria():
    #  Accurate scope is substantive: it distinguishes a useful review result
    #  from a misleading endorsement.
    d = {"repo": "https://github.com/quien/que", "commit": "a" * 40,
         "carpeta": ""}
    res = {"ok": True, "commit": "a" * 40,
           "plugin": {"id": "x", "title": "X", "description": "d",
                      "permisos": []}}
    texto, _ = publish.informe(d, [], res)
    contiene("the report states its scope", texto, "not a security audit")


def main():
    pruebas = [v for k, v in sorted(globals().items())
               if k.startswith("prueba_")]
    for p in pruebas:
        p()

    if fallos:
        print("%d failed checks across %d tests:\n" % (len(fallos), len(pruebas)))
        for f in fallos:
            print("  " + f + "\n")
        return 1
    print("%d tests, all passed." % len(pruebas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
