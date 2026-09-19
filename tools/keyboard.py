#!/usr/bin/env python3
"""Virtual uinput keyboard for tests that need real key events.

    python3 keyboard.py escribe hola
    python3 keyboard.py pulsa ESC ENTER TAB
    python3 keyboard.py manten CTRL 3     # three seconds, for ctrl+wheel

The compositor rejects synthetic Wayland key events but accepts kernel input
devices. A uinput keyboard appears like a physical keyboard.
"""
import ctypes, fcntl, os, struct, sys, time

UI = ord('U')


def _iow(nr, size):
    return (1 << 30) | (size << 16) | (UI << 8) | nr


def _io(nr):
    return (UI << 8) | nr


UI_DEV_CREATE = _io(1)
UI_DEV_DESTROY = _io(2)
UI_DEV_SETUP = _iow(3, 92)
UI_SET_EVBIT = _iow(100, 4)
UI_SET_KEYBIT = _iow(101, 4)

EV_KEY, EV_SYN = 0x01, 0x00
SYN_REPORT = 0

KEY_LEFTSHIFT = 42

# US layout, interpreted by the compositor unless configured otherwise.
NORMAL = {
    **{c: 2 + i for i, c in enumerate("1234567890")},
    **{c: 16 + i for i, c in enumerate("qwertyuiop")},
    **{c: 30 + i for i, c in enumerate("asdfghjkl")},
    **{c: 44 + i for i, c in enumerate("zxcvbnm")},
    " ": 57, "-": 12, "=": 13, "[": 26, "]": 27, ";": 39,
    "'": 40, "`": 41, "\\": 43, ",": 51, ".": 52, "/": 53,
}
CON_SHIFT = {
    "!": 2, "@": 3, "#": 4, "$": 5, "%": 6, "^": 7, "&": 8, "*": 9,
    "(": 10, ")": 11, "_": 12, "+": 13, "{": 26, "}": 27, ":": 39,
    '"': 40, "~": 41, "|": 43, "<": 51, ">": 52, "?": 53,
}
ESPECIALES = {
    "ESC": 1, "BACKSPACE": 14, "TAB": 15, "ENTER": 28, "SPACE": 57,
    "UP": 103, "DOWN": 108, "LEFT": 105, "RIGHT": 106,
    "DELETE": 111, "HOME": 102, "END": 107, "PAGEUP": 104, "PAGEDOWN": 109,
    "PRINT": 99, "SUPER": 125, "ALT": 56, "SHIFT": 42, "CTRL": 29,
}


def codigo(caracter):
    """Return (keycode, shift required) for a single character."""
    bajo = caracter.lower()
    if caracter in CON_SHIFT:
        return CON_SHIFT[caracter], True
    if bajo in NORMAL:
        return NORMAL[bajo], caracter.isupper()
    return None, False


class Teclado:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        # Enable the normal key range rather than declaring keys individually.
        for tecla in range(1, 128):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, tecla)

        nombre = b"k4-teclado-de-pruebas" + b"\0" * (80 - 21)
        fcntl.ioctl(self.fd, UI_DEV_SETUP,
                    struct.pack("HHHH80sI", 0x03, 0x1234, 0x5678, 1, nombre, 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # Give udev and the compositor time to discover the new keyboard;
        # otherwise the first key events are lost.
        time.sleep(1.2)

    def evento(self, tipo, codigo_, valor):
        os.write(self.fd, struct.pack("llHHi", 0, 0, tipo, codigo_, valor))

    def sync(self):
        self.evento(EV_SYN, SYN_REPORT, 0)

    def pulsar(self, codigo_, shift=False):
        if shift:
            self.evento(EV_KEY, KEY_LEFTSHIFT, 1)
        self.evento(EV_KEY, codigo_, 1)
        self.sync()
        time.sleep(0.012)
        self.evento(EV_KEY, codigo_, 0)
        if shift:
            self.evento(EV_KEY, KEY_LEFTSHIFT, 0)
        self.sync()
        time.sleep(0.03)

    def escribir(self, texto):
        for caracter in texto:
            c, shift = codigo(caracter)
            if c is None:
                print("no keycode for %r; skipping" % caracter, file=sys.stderr)
                continue
            self.pulsar(c, shift)

    def cerrar(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    orden, resto = sys.argv[1], sys.argv[2:]
    t = Teclado()
    try:
        if orden == "escribe":
            t.escribir(" ".join(resto))
        elif orden == "pulsa":
            for nombre in resto:
                # "SUPER+ALT+PRINT" is a chord: hold modifiers while pressing
                # and releasing the last key.
                partes = [x for x in nombre.upper().split("+") if x]
                codigos = []
                for parte in partes:
                    if parte in ESPECIALES:
                        codigos.append(ESPECIALES[parte])
                    else:
                        c, _ = codigo(parte.lower())
                        if c is not None:
                            codigos.append(c)
                if not codigos:
                    continue
                for c in codigos[:-1]:
                    t.evento(EV_KEY, c, 1)
                t.sync()
                t.pulsar(codigos[-1])
                for c in reversed(codigos[:-1]):
                    t.evento(EV_KEY, c, 0)
                t.sync()
        elif orden == "manten":
            #  Hold a modifier for tests such as ctrl+wheel. Separate press
            #  and release processes would destroy their uinput devices on
            #  exit, releasing the key early. Keep this device alive while
            #  another process moves the mouse.
            nombre = resto[0].upper()
            if nombre not in ESPECIALES:
                print("cannot hold unknown key %s" % nombre, file=sys.stderr)
                return 1
            segundos = float(resto[1]) if len(resto) > 1 else 2.0
            t.evento(EV_KEY, ESPECIALES[nombre], 1)
            t.sync()
            time.sleep(segundos)
            t.evento(EV_KEY, ESPECIALES[nombre], 0)
            t.sync()
        else:
            print("unknown command: %s" % orden, file=sys.stderr)
            return 1
    finally:
        t.cerrar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
