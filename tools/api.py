#!/usr/bin/env python3
"""Check plugin imports, platform types, and API documentation coverage.

    python3 tools/api.py

The architecture requires plugins to import only QtQuick and K4. This checker
does NOT yet enforce that full boundary: it also accepts other Qt modules and
quoted path imports, including host imports still awaiting migration.

It rejects direct Quickshell imports and selected unwrapped platform types.
Keeping platform access behind K4 makes plugins portable to another host and
gives authors a small, documented API instead of all of Quickshell.

Services in services/ may use Quickshell directly: they implement the host,
not the public API. Platform functionality belongs in api/K4 or a service.
"""
import pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent


def revisar_documentacion():
    """Require every public API type to appear in the guides.

    This check was added after twelve types went undocumented. Missing types
    now fail a tool check rather than relying on someone remembering to look.

    `Puente` is deliberately excluded: it connects the host and API and is not
    intended for plugins to use directly.
    """
    qmldir = (RAIZ / "api" / "K4" / "qmldir").read_text()
    tipos = [t for t in re.findall(r"^(?:singleton )?([A-Z]\w+) 1\.0",
                                   qmldir, re.M)
             if t != "Puente"]
    fallos = []
    #  Check both the full plugin guide and the api/README.md quick reference.
    #  Types documented in only one guide leave the other incomplete.
    for doc in ("docs/PLUGINS.md", "api/README.md"):
        texto = (RAIZ / doc).read_text()
        for t in tipos:
            if not re.search(r"\bK4\.%s\b" % t, texto):
                fallos.append("api/K4/%s.qml is not mentioned in %s" % (t, doc))
    return fallos


def revisar_api():
    """The reverse boundary: api/K4 files must not import the bar.

    K4 resolves through file://, so a relative import from inside it loads a
    SECOND copy of services/ and core/: two PluginManager instances, two sets
    of plugins, and duplicate IPC registrations. API dependencies are injected
    through Puente (api/K4/Puente.qml).
    """
    fallos = []
    for f in sorted((RAIZ / "api" / "K4").glob("*.qml")):
        for n, linea in enumerate(f.read_text().split("\n"), 1):
            limpia = re.sub(r"//.*$", "", linea)
            if re.search(r'import\s+"\.\./', limpia):
                fallos.append("api/K4/%s:%d imports the bar through a "
                              "relative path: %s" % (f.name, n, limpia.strip()))
    return fallos

#  Imports currently accepted by this checker, not the full architecture rule.
#  Other Qt modules and quoted paths such as "../../core" still pass here.
#  Existing host imports need migration before enforcing QtQuick/K4 only.
PERMITIDOS = re.compile(
    r"^import\s+(Qt\w*(\.\w+)*|K4(\s+as\s+\w+)?|\"[^\"]+\"(\s+as\s+\w+)?)\s*$"
)

# Types that reveal platform access through another route.
SOSPECHOSOS = [
    "Quickshell", "IpcHandler", "SplitParser", "StdioCollector", "FileView",
    "PanelWindow", "WlrLayershell", "WlSessionLock", "GlobalShortcut",
    "DesktopEntries", "QsMenuOpener", "IconImage", "PamContext", "LazyLoader",
]


def sin_comentarios(texto):
    """Strip // comments so documentation mentions do not trigger findings."""
    return "\n".join(re.sub(r"//.*$", "", l) for l in texto.split("\n"))


def revisar(fichero):
    fallos = []
    texto = fichero.read_text()
    relativa = fichero.relative_to(RAIZ)

    for n, linea in enumerate(texto.split("\n"), 1):
        pelada = linea.strip()
        if not pelada.startswith("import "):
            continue
        if not PERMITIDOS.match(pelada):
            fallos.append((relativa, n, pelada, "import outside the accepted API boundary"))

    limpio = sin_comentarios(texto)
    for tipo in SOSPECHOSOS:
        for m in re.finditer(r"\b" + tipo + r"\b", limpio):
            n = limpio[:m.start()].count("\n") + 1
            fallos.append((relativa, n, tipo, "unwrapped platform type"))

    return fallos


def main():
    ficheros = sorted((RAIZ / "plugins").rglob("*.qml"))
    if not ficheros:
        print("no plugin QML files found in plugins/; check the checkout path",
              file=sys.stderr)
        return 2

    todos = []
    for f in ficheros:
        todos.extend(revisar(f))

    sin_doc = revisar_documentacion()
    if sin_doc:
        print("The API exposes types missing from the guides:\n")
        for x in sin_doc:
            print("  " + x)
        print("\nPublic types must be documented so plugin authors can find them.")
        return 1

    #  The reverse boundary prevents duplicate host instances: see revisar_api().
    dobles = revisar_api()
    if dobles:
        print("The API imports the bar through relative paths:\n")
        for x in dobles:
            print("  " + x)
        print("\nThis loads a SECOND copy of services/ and core/: two")
        print("PluginManager instances, duplicate plugins and IPC registrations.")
        print("Inject API dependencies from shell.qml through api/K4/Puente.qml.")
        return 1

    if not todos:
        print("%d files checked; current import/type checks passed "
              "(QtQuick/K4-only imports are not yet enforced)." % len(ficheros))
        return 0

    print("Found %d API boundary violations:\n" % len(todos))
    for ruta, n, que, porque in todos:
        print("  %s:%d  %s  (%s)" % (ruta, n, que, porque))
    print("\nAdd missing platform functionality to api/K4 or a host service.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
