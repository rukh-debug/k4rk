#!/usr/bin/env python3
"""Check for manually positioned direct children of layouts.

    python3 tools/layouts.py

A QQuickLayout — RowLayout, ColumnLayout, GridLayout or StackLayout — controls
the x, y, width and height of its visible children. Direct children must not
set those properties or anchors themselves. Without an implicit size, a child
such as MouseArea can end up measuring 0×0.

This can silently disable interaction. The dungeon pill let clicks through to
the control center, and Ask image actions stopped responding to hover or click.
Removing anchors silenced Qt warnings without fixing geometry ownership.

Use Layout.preferredWidth and related sizing hints, and Layout.alignment for
placement. To anchor a MouseArea over a whole row, wrap the row in an Item
sized from it and parent the anchored element to that Item.

Coverage is limited to DIRECT layout children with explicit geometry. It does
not detect missing implicit sizes or manually reassigned visual `parent`s.
"""
import pathlib, re, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent

LAYOUTS = ("RowLayout", "ColumnLayout", "GridLayout", "StackLayout")

#  Geometry controlled by the layout rather than its children.
#
#  No `^`: match() anchors at the supplied position, whereas `^` requires the
#  start of the string. The first version used it and missed eight violations.
GEOM = re.compile(r"(x|y|width|height|anchors)\s*[:.]")

#  An element opening, including qualified names such as `K4.Process`.
ELEM = re.compile(r"([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\s*\{")


def sin_ruido(texto):
    """Blank comments and strings while preserving the total length.

    Their braces and colons must not affect parsing. Spaces preserve offsets
    into the original text, which is used to calculate line numbers.
    """
    salida, i, n = [], 0, len(texto)
    while i < n:
        c = texto[i]
        if c == "/" and i + 1 < n and texto[i + 1] == "/":
            j = texto.find("\n", i)
            j = n if j < 0 else j
        elif c == "/" and i + 1 < n and texto[i + 1] == "*":
            j = texto.find("*/", i + 2)
            j = n if j < 0 else j + 2
        elif c in "\"'":
            j = i + 1
            while j < n and texto[j] != c:
                j += 2 if texto[j] == "\\" else 1
            j = min(j + 1, n)
        else:
            salida.append(c)
            i += 1
            continue
        salida.append(" " * (j - i))
        i = j
    return "".join(salida)


def revisar(texto):
    """Find explicit geometry on direct layout children."""
    limpio = sin_ruido(texto)
    pila, prof, avisos = [], 0, []
    i, n = 0, len(limpio)

    while i < n:
        c = limpio[i]

        if c == "{":
            #  Identify the element opening that ends at this brace.
            tipo = None
            for m in ELEM.finditer(limpio, max(0, i - 160), i + 1):
                if m.end() == i + 1:
                    tipo = m.group(1)
            prof += 1
            pila.append((tipo, prof))
            i += 1
            continue

        if c == "}":
            if pila and pila[-1][1] == prof:
                pila.pop()
            prof -= 1
            i += 1
            continue

        #  Does a statement start here and set layout-controlled geometry?
        if c.isalpha() and (i == 0 or limpio[i - 1] in "\n\t ;{"):
            m = GEOM.match(limpio, i)
            if m:
                if len(pila) >= 2 and pila[-1][0] and pila[-2][0] in LAYOUTS:
                    linea = texto.count("\n", 0, i) + 1
                    avisos.append((linea, pila[-2][0], pila[-1][0], m.group(1)))
                i = m.end()
                continue

        i += 1

    return avisos


#  A real broken case. Run this control before scanning the repository so a
#  detector that stops recognizing violations cannot report a false clean run.
CONTROL = """
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: indicador
    spacing: 4

    Text { text: "hello"; Layout.alignment: Qt.AlignVCenter }

    MouseArea {
        x: -3
        y: -3
        width: indicador.width + 6
        height: indicador.height + 6
        onClicked: indicador.abrir()
    }
}
"""


def autocomprobar():
    """Verify detection; return an error description or None on success."""
    salida = revisar(CONTROL)
    fijadas = sorted(set(p for _, _, _, p in salida))
    if fijadas != ["height", "width", "x", "y"]:
        return ("control case must report x, y, width and height; reported: "
                + (", ".join(fijadas) if fijadas else "nothing"))
    return None


def main():
    fallo = autocomprobar()
    if fallo:
        print("The checker is broken:", fallo)
        print("\nA zero-result scan would be meaningless; refusing to pass.")
        return 1

    ficheros = sorted(RAIZ.rglob("*.qml"))
    todos = []
    for ruta in ficheros:
        if ".git" in ruta.parts:
            continue
        for linea, layout, hijo, prop in revisar(ruta.read_text(encoding="utf-8")):
            todos.append((ruta.relative_to(RAIZ), linea, layout, hijo, prop))

    if not todos:
        print("%d files checked; no explicit geometry on direct layout children."
              % len(ficheros))
        return 0

    print("Found %d explicit geometry assignments inside layouts:\n" % len(todos))
    for ruta, linea, layout, hijo, prop in todos:
        print("  %s:%d  %s inside %s sets '%s'" % (ruta, linea, hijo, layout, prop))
    print("\nLayouts control child geometry. Without an implicit size, a child")
    print("can become 0×0 and silently stop responding. Use Layout.preferredWidth")
    print("and Layout.alignment. For anchors, wrap the row in an Item sized from")
    print("it and parent the anchored element to that Item.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
