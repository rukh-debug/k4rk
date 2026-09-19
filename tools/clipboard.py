#!/usr/bin/env python3
"""Clipboard history storage.

Quickshell exposes `clipboardText`, but in Wayland testing its change signal
missed other applications' copies and even the initial contents. Instead,
`wl-paste --watch` runs this script on each copy.

Commands:

    save text|image        read clipboard data from stdin and store it
    list                   emit the JSON index, pinned first then newest
    copy <id>              put that entry back on the clipboard
    delete <id>            remove the entry
    pin <id>               toggle pinning; pinned entries do not expire
    clear                  remove every unpinned entry

Each entry has its own file; the index holds only what the list view needs.
Content hashes identify entries, so copying the same content moves it to the
top instead of creating a duplicate.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

BASE = os.path.expanduser("~/.local/state/k4/portapapeles")
DATOS = os.path.join(BASE, "datos")
INDICE = os.path.join(BASE, "indice.json")

TOPE_ENTRADAS = 300
TOPE_BYTES = 8 * 1024 * 1024      # larger copies are not worth retaining
#  Also cap total storage: 300 large images could consume hundreds of MB.
#  History is a convenience, not an archive; old entries make room for new ones.
TOPE_TOTAL = 50 * 1024 * 1024
RESUMEN = 400                     # preview length stored for the list row


# ── index ────────────────────────────────────────────────────────────

def carga():
    try:
        with open(INDICE) as f:
            d = json.load(f)
        return d.get("entradas", [])
    except Exception:
        return []


def guarda(entradas):
    os.makedirs(BASE, exist_ok=True)
    tmp = INDICE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"entradas": entradas}, f)
    os.replace(tmp, INDICE)


def ruta(ident):
    return os.path.join(DATOS, ident)


# ── content labels ───────────────────────────────────────────────────
#
#  Short labels help identify colors and links among hundreds of text entries.

RE_URL = re.compile(r"^\s*(https?|ftp|ssh|magnet)://\S+\s*$", re.I)
RE_COLOR = re.compile(r"^\s*#[0-9a-fA-F]{3,8}\s*$")
RE_RUTA = re.compile(r"^\s*[~/][^\s\0]*\s*$")
RE_ORDEN = re.compile(r"^\s*(sudo|git|npm|pnpm|yarn|cargo|python3?|pip|docker|"
                      r"systemctl|pacman|yay|ssh|scp|curl|wget|make|cmake|kubectl)\b")


def etiqueta(texto):
    if RE_URL.match(texto):
        return "link"
    if RE_COLOR.match(texto):
        return "color"
    if RE_RUTA.match(texto) and len(texto) < 300:
        return "path"
    if RE_ORDEN.match(texto):
        return "command"
    if "\n" in texto.strip() and re.search(r"[{};()=]|^\s{2,}", texto, re.M):
        return "code"
    return ""


def es_secreto():
    """Check whether a password manager marked the clipboard offer.

    Password-manager hints tell history tools not to store the content.
    If MIME-type discovery fails, this function currently returns False.
    """
    try:
        tipos = subprocess.run(["wl-paste", "--list-types"],
                               capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return False
    return "password" in tipos.lower() or "x-kde-passwordManagerHint" in tipos


# ── save ─────────────────────────────────────────────────────────────

def guardar(tipo):
    bruto = sys.stdin.buffer.read()
    if not bruto or len(bruto) > TOPE_BYTES:
        return

    if tipo == "text":
        try:
            texto = bruto.decode("utf-8")
        except UnicodeDecodeError:
            return
        if not texto.strip():
            return
        if es_secreto():
            return
        resumen = texto[:RESUMEN]
        marca = etiqueta(texto)
        mime = "text/plain"
    else:
        resumen = ""
        marca = "image"
        mime = "image/png"

    ident = hashlib.sha1(bruto).hexdigest()[:16]
    entradas = carga()

    # Existing entry: move to the top and preserve its pinned state.
    previa = None
    for e in entradas:
        if e["id"] == ident:
            previa = e
            break
    if previa:
        entradas.remove(previa)
        previa["cuando"] = time.time()
        entradas.insert(0, previa)
        guarda(entradas)
        print("nuevo", flush=True)
        return

    os.makedirs(DATOS, exist_ok=True)
    with open(ruta(ident), "wb") as f:
        f.write(bruto)

    entradas.insert(0, {
        "id": ident,
        "tipo": tipo,
        "mime": mime,
        "resumen": resumen,
        "etiqueta": marca,
        "bytes": len(bruto),
        "lineas": resumen.count("\n") + 1 if tipo == "text" else 0,
        "cuando": time.time(),
        "fijado": False,
    })

    podar(entradas)
    guarda(entradas)
    print("nuevo", flush=True)


def podar(entradas):
    """Trim oldest entries by count AND total bytes, preserving pinned ones."""
    sobran = max(0, len(entradas) - TOPE_ENTRADAS)

    def peso(e):
        try:
            return os.path.getsize(ruta(e["id"]))
        except OSError:
            return 0

    total = sum(peso(e) for e in entradas)

    for e in reversed(list(entradas)):
        if sobran <= 0 and total <= TOPE_TOTAL:
            break
        if e.get("fijado"):
            continue
        total -= peso(e)
        entradas.remove(e)
        try:
            os.remove(ruta(e["id"]))
        except OSError:
            pass
        sobran -= 1


# ── remaining commands ───────────────────────────────────────────────

def listar():
    # Pinned first, then newest within each group.
    entradas = carga()
    entradas.sort(key=lambda e: (not e.get("fijado"), -e.get("cuando", 0)))
    for e in entradas:
        e["ruta"] = ruta(e["id"])
    print(json.dumps({"entradas": entradas}), flush=True)


def copiar(ident):
    entradas = carga()
    for e in entradas:
        if e["id"] != ident:
            continue
        try:
            with open(ruta(ident), "rb") as f:
                datos = f.read()
        except OSError:
            return
        # Set --type explicitly so wl-copy does not guess and paste image
        # bytes as text.
        subprocess.run(["wl-copy", "--type", e.get("mime", "text/plain")],
                       input=datos, check=False)
        return


def borrar(ident):
    entradas = [e for e in carga() if e["id"] != ident]
    try:
        os.remove(ruta(ident))
    except OSError:
        pass
    guarda(entradas)
    print("nuevo", flush=True)


def fijar(ident):
    entradas = carga()
    for e in entradas:
        if e["id"] == ident:
            e["fijado"] = not e.get("fijado", False)
    guarda(entradas)
    print("nuevo", flush=True)


def limpiar():
    entradas = carga()
    quedan = [e for e in entradas if e.get("fijado")]
    conservados = {e["id"] for e in quedan}

    for e in entradas:
        if e["id"] in conservados:
            continue
        try:
            os.remove(ruta(e["id"]))
        except OSError:
            pass

    guarda(quedan)
    print("nuevo", flush=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    orden = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else ""

    if orden == "save":
        guardar(arg or "text")
    elif orden == "list":
        listar()
    elif orden == "copy":
        copiar(arg)
    elif orden == "delete":
        borrar(arg)
    elif orden == "pin":
        fijar(arg)
    elif orden == "clear":
        limpiar()


if __name__ == "__main__":
    main()
