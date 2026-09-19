#!/usr/bin/env python3
"""Require explicit formatting for interface text sinks.

QML `Text` defaults to `AutoText`, interpreting strings that resemble markup.
Notifications, clipboard contents, window titles, song names and filenames
come from outside the bar. A notification containing `<img src="http://…">`
could cause QML to fetch a remote image, acting as a read beacon.

In testing, `<img src="x.png" width=400 height=60>` measured 475x60 with
AutoText (the image box) and 440x19 with PlainText (the literal text).

Fail when a text sink lacks an explicit `textFormat`. Intentional rich text,
such as `textFormat: TextEdit.MarkdownText` in Ask, is accepted. This check
requires an explicit choice rather than banning formatting.
"""

import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARPETAS = ["core", "widgets", "services", "plugins", os.path.join("api", "K4")]

#  Types that interpret markup. TextInput is always plain text.
ABRE = re.compile(r'(?<![A-Za-z_.])(Text|TextEdit)\s*\{')


def cuerpo(texto, i):
    """Return the body of the block opening at `i`, counting braces."""
    hondo, j = 0, i
    while j < len(texto):
        if texto[j] == "{":
            hondo += 1
        elif texto[j] == "}":
            hondo -= 1
            if hondo == 0:
                return texto[i:j]
        j += 1
    return texto[i:]


def qmls():
    for carpeta in CARPETAS:
        d = os.path.join(RAIZ, carpeta)
        for base, _, ficheros in os.walk(d):
            for n in sorted(ficheros):
                if n.endswith(".qml"):
                    yield os.path.join(base, n)


def main():
    fallos, mirados = [], 0
    for ruta in qmls():
        texto = open(ruta, encoding="utf-8").read()
        #  Ignore comments: a documented `Text {` is not a text sink.
        limpio = re.sub(r'//[^\n]*', '', texto)
        for m in ABRE.finditer(limpio):
            mirados += 1
            if "textFormat" not in cuerpo(limpio, m.end() - 1):
                fallos.append("%s:%d" % (os.path.relpath(ruta, RAIZ),
                                         limpio[:m.start()].count("\n") + 1))

    if fallos:
        print("%d text sinks without `textFormat`:\n" % len(fallos))
        for f in fallos:
            print("  " + f)
        print("\nSet `textFormat: Text.PlainText` or another intentional format.")
        return 1
    print("%d text sinks checked; all declare their format." % mirados)
    return 0


if __name__ == "__main__":
    sys.exit(main())
