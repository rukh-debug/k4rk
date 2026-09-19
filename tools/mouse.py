#!/usr/bin/env python3
"""Virtual uinput mouse for tests that need real pointer events.

    mouse.py mueve 960 540      # move to this screen position
    mouse.py clic               # left-click at the current position
    mouse.py clic 960 540       # move and click
    mouse.py derecho 960 540
    mouse.py donde              # current position
    mouse.py rueda 3            # three notches up (negative for down)
    mouse.py arrastra 100 200 400 200      # drag in multiple steps
    mouse.py guion "mueve 900 17" "espera 1" "arrastra 900 300 1100 300"

Companion to keyboard.py: the compositor rejects synthetic Wayland events but
treats a kernel input device like a physical mouse.

Use relative motion: libinput treats absolute devices as tablets or touch
screens with their own mappings. Relative motion can start from a corner,
where the pointer stops at the edge. Query Hyprland to verify the resulting
position rather than trusting accumulated movement.
"""
import fcntl, os, socket, struct, sys, time

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
UI_SET_RELBIT = _iow(102, 4)

EV_KEY, EV_REL, EV_SYN = 0x01, 0x02, 0x00
REL_X, REL_Y, REL_WHEEL = 0x00, 0x01, 0x08
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
SYN_REPORT = 0

BOTONES = {"clic": BTN_LEFT, "izquierdo": BTN_LEFT,
           "derecho": BTN_RIGHT, "medio": BTN_MIDDLE}


def donde():
    """Return Hyprland's cursor position, or None."""
    firma = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    ruta = "%s/hypr/%s/.socket.sock" % (runtime, firma)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(ruta)
        s.sendall(b"cursorpos")
        d = s.recv(256).decode()
        s.close()
        x, y = d.split(",")
        return int(x.strip()), int(y.strip())
    except (OSError, ValueError):
        return None


class Raton:
    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for b in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, b)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
        for r in (REL_X, REL_Y, REL_WHEEL):
            fcntl.ioctl(self.fd, UI_SET_RELBIT, r)

        nombre = b"k4-raton-de-pruebas"
        nombre += b"\0" * (80 - len(nombre))
        fcntl.ioctl(self.fd, UI_DEV_SETUP,
                    struct.pack("HHHH80sI", 0x03, 0x1234, 0x5679, 1, nombre, 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        # Give the compositor time to discover the new device.
        time.sleep(1.2)

    def evento(self, tipo, codigo, valor):
        os.write(self.fd, struct.pack("llHHi", 0, 0, tipo, codigo, valor))

    def sync(self):
        self.evento(EV_SYN, SYN_REPORT, 0)

    def paso(self, dx, dy):
        # Move in small steps: pointer acceleration can distort a large jump.
        while dx or dy:
            px = max(-100, min(100, dx))
            py = max(-100, min(100, dy))
            if px:
                self.evento(EV_REL, REL_X, px)
            if py:
                self.evento(EV_REL, REL_Y, py)
            self.sync()
            dx -= px
            dy -= py
            time.sleep(0.002)

    def ir_a(self, x, y):
        """Move to a screen position, correcting with Hyprland feedback."""
        #  Move from the known position when possible. Visiting a corner first
        #  leaves the hovered surface and closes hover-only island controls
        #  before they can be clicked.
        p = donde()
        if p is not None:
            self.paso(x - p[0], y - p[1])
        else:
            self.paso(-6000, -6000)
            time.sleep(0.08)
            self.paso(x, y)
        time.sleep(0.08)

        # Correct any drift caused by pointer acceleration.
        for _ in range(4):
            p = donde()
            if p is None:
                return
            dx, dy = x - p[0], y - p[1]
            if abs(dx) <= 1 and abs(dy) <= 1:
                return
            self.paso(dx, dy)
            time.sleep(0.06)

    def abajo(self, boton=BTN_LEFT):
        self.evento(EV_KEY, boton, 1)
        self.sync()
        time.sleep(0.04)

    def arriba(self, boton=BTN_LEFT):
        self.evento(EV_KEY, boton, 0)
        self.sync()
        time.sleep(0.05)

    def pulsar(self, boton):
        self.abajo(boton)
        self.arriba(boton)

    def rueda(self, muescas):
        self.evento(EV_REL, REL_WHEEL, muescas)
        self.sync()
        time.sleep(0.05)

    def arrastrar(self, x0, y0, x1, y1, tramos=12):
        """Drag in multiple steps.

        A single jump misses intermediate positions needed by QML gestures
        driven by onPositionChanged. Twelve steps with short pauses give the
        interface time to react.
        """
        self.ir_a(x0, y0)
        self.abajo()
        for i in range(1, tramos + 1):
            objetivo_x = round(x0 + (x1 - x0) * i / tramos)
            objetivo_y = round(y0 + (y1 - y0) * i / tramos)
            # Query each step so acceleration drift does not accumulate and
            # cause a drop at the wrong position. A query measured 0.02 ms.
            p = donde()
            if p is None:
                break
            self.paso(objetivo_x - p[0], objetivo_y - p[1])
            time.sleep(0.02)

        p = donde()
        if p is not None:
            self.paso(x1 - p[0], y1 - p[1])
        time.sleep(0.05)
        self.arriba()

    def cerrar(self):
        fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    orden = sys.argv[1]

    if orden == "donde":
        print(donde())
        return 0

    r = Raton()
    try:
        if orden == "guion":
            #  Run a sequence with ONE device. Creating a new mouse for each
            #  step loses hover state, hiding hover-only island chips or menus.
            #
            #      mouse.py guion "mueve 900 17" "espera 1.5" "clic 1217 31"
            for paso in sys.argv[2:]:
                trozos = paso.split()
                if trozos[0] == "mueve":
                    r.ir_a(int(trozos[1]), int(trozos[2]))
                elif trozos[0] == "espera":
                    time.sleep(float(trozos[1]))
                elif trozos[0] == "abajo":
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.abajo()
                elif trozos[0] == "arriba":
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.arriba()
                elif trozos[0] == "rueda":
                    r.rueda(int(trozos[1]))
                elif trozos[0] == "arrastra":
                    r.arrastrar(int(trozos[1]), int(trozos[2]),
                                int(trozos[3]), int(trozos[4]),
                                int(trozos[5]) if len(trozos) > 5 else 12)
                elif trozos[0] in BOTONES:
                    if len(trozos) >= 3:
                        r.ir_a(int(trozos[1]), int(trozos[2]))
                    r.pulsar(BOTONES[trozos[0]])
                print(trozos[0], donde(), flush=True)
        elif orden == "mueve":
            r.ir_a(int(sys.argv[2]), int(sys.argv[3]))
        elif orden == "rueda":
            r.rueda(int(sys.argv[2]))
        elif orden == "arrastra":
            r.arrastrar(int(sys.argv[2]), int(sys.argv[3]),
                        int(sys.argv[4]), int(sys.argv[5]),
                        int(sys.argv[6]) if len(sys.argv) > 6 else 12)
        elif orden in BOTONES:
            if len(sys.argv) >= 4:
                r.ir_a(int(sys.argv[2]), int(sys.argv[3]))
            r.pulsar(BOTONES[orden])
        else:
            print("unknown command: %s" % orden, file=sys.stderr)
            return 1
        time.sleep(0.15)
        print(donde())
    finally:
        r.cerrar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
