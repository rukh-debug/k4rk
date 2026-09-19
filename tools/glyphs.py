#!/usr/bin/env python3
"""Check that each named icon matches its glyph.

    python3 tools/glyphs.py            check the entire project
    python3 tools/glyphs.py blur       search names and show codepoints

UI icons are Nerd Font glyphs represented by numbers such as `0x000F02E9`,
with a comment naming the icon. A mismatch can display the wrong symbol.

Compare comments with the font's own glyph names rather than relying on
memory. Only codepoints with named comments such as `// md-blur` are checked;
unnamed icons make no claim to verify.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#  Match `0x000F02E9   // md-image` and `0xF0190), // md-content_cut`.
#  Allow punctuation between the codepoint and comment.
RE_ICONO = re.compile(
    r"0x0*([0-9A-Fa-f]{4,6})\s*[,)\]]*\s*//\s*([a-z]{2,5}-[a-z0-9_]+)")


def fuente():
    """Ask fontconfig for the Nerd Font file."""
    import subprocess
    for familia in ("MesloLGS Nerd Font Mono", "MesloLGS Nerd Font",
                    "Symbols Nerd Font"):
        p = subprocess.run(["fc-match", "-f", "%{file}", familia],
                           capture_output=True, text=True)
        ruta = p.stdout.strip()
        if ruta and "Nerd" in ruta:
            return ruta
    return ""


def nombres():
    from fontTools.ttLib import TTFont
    ruta = fuente()
    if not ruta:
        print("Cannot find the Nerd Font. Is ttf-meslo-nerd installed?")
        sys.exit(2)
    f = TTFont(ruta, fontNumber=0)
    return ruta, f.getBestCmap()


def ficheros():
    for base, dirs, hojas in os.walk(RAIZ):
        dirs[:] = [d for d in dirs if d not in (".git",)]
        for h in hojas:
            if h.endswith(".qml"):
                yield os.path.join(base, h)


def revisar():
    ruta, cmap = nombres()
    print("Font: %s\n" % ruta)

    revisados = malos = 0
    for f in sorted(ficheros()):
        for n, linea in enumerate(open(f, encoding="utf-8"), 1):
            m = RE_ICONO.search(linea)
            if not m:
                continue
            cp = int(m.group(1), 16)
            dice = m.group(2)
            real = cmap.get(cp)
            revisados += 1
            if real == dice:
                continue
            malos += 1
            print("  %s:%d" % (os.path.relpath(f, RAIZ), n))
            print("   claimed: %s" % dice)
            print("    actual: %s" % (real or "(no glyph at this codepoint)"))
            #  Show the intended glyph's codepoint to make correction easy.
            for c, nombre in cmap.items():
                if nombre == dice:
                    print("  found at: 0x%06X" % c)
                    break

    print("\n%d named icons, %d incorrect." % (revisados, malos))
    return 1 if malos else 0


def buscar(texto):
    ruta, cmap = nombres()
    hits = sorted((n, c) for c, n in cmap.items() if texto.lower() in n.lower())
    if not hits:
        print("No matches for '%s'." % texto)
        return 1
    for nombre, cp in hits[:40]:
        print("  0x%06X   %s" % (cp, nombre))
    if len(hits) > 40:
        print("  … and %d more." % (len(hits) - 40))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(buscar(sys.argv[1]) if len(sys.argv) > 1 else revisar())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
