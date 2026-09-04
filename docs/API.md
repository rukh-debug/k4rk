# k4 public API

This is the public surface available to plugins. The API lives in `api/K4/`; the
source files contain additional implementation notes.

## Imports

A plugin imports Qt and k4:

```qml
import QtQuick
import K4 as K4
```

Start the host with `arrancar`. It adds `api/` to `QML_IMPORT_PATH`; launching
`quickshell -p shell.qml` directly will not resolve `import K4`.

Qt (`QtQuick`, `QtMultimedia`, `Timer`, animations, and so on) is the portable
layer. Quickshell and Wayland should stay behind a `K4` API type whenever an
equivalent exists.

## Plugin contract

`K4Plugin` is the root object of a module:

| Property | Meaning |
|---|---|
| `name` | Stable, unique plugin ID |
| `title` | Human-readable name |
| `habilitado` | Persistent user permission |
| `active` | Requests the island right now |
| `priority` | Arbitration priority |
| `transitorio` | View that appears unasked and expires on its own; it closes the moment another plugin takes the island |
| `islandWidth`, `islandHeight` | Requested island size |
| `view` | Component rendered by the host |
| `viewLoaded` | Keep the size while the view closes |
| `grabKeyboard` | Exclusive keyboard focus |
| `tecladoOpcional` | On-demand keyboard focus |
| `tecladoAlPasar` | Exclusive keyboard focus only while the pointer is over the island (for games) |
| `closeOnHoverExit` | Enable hover-exit timeout |
| `colocable` | Your surface is a summoned view: it gets a card in Settings → Placement. Only what OPENS gets placed — the pill's wings, transients and indicators do not |

The host also knows a few optional verbs. They exist as no-op stubs on
the contract, so a plugin overrides the ones it serves and the host can
call unconditionally: `toggle(tab)`, `openTab(tab)`,
`abrirPagina(page)`, `buscar(query)`, `preguntar(texto)`,
`openAsk(selection)`, `attachScreenshot()`, `attachRegion()`,
`refresh()`, `updateAll()`, `updateSelected()`. If your view
is addressable — a tab, a landing page, a search to start with — serve
the verb instead of letting the caller poke properties. The same names
are how one plugin talks to another: Apps reaches Packages through
`refresh()` and `updateAll()`, the launcher lands on Apps' updates mode
through `openTab("updates")`, and nobody remembers a method name only
one side knows.

`active` and `habilitado` are different states:

```qml
K4Plugin {
    name: "hello"
    active: habilitado && abierto
    property bool abierto: false
}
```

Repo modules import that root type from `core/`; third-party plugins use the
same contract as `K4.Plugin`.

### Reaching another plugin: declare its id

Plugins never import each other. A plugin that needs another declares a
property NAMED like the other's catalog id, and the host fills it with the
live instance — or `null` when that plugin is off, broken or unloaded:

```qml
K4Plugin {
    name: "mine"
    property var panel: null      // the control centre, or null
    property var packages: null   // whatever you need, by id
}
```

Guard every use (`panel ? panel.open : false`); the reference goes null the
moment its plugin dies, and comes back when it returns.

### Requiring a binary: `require: "bin:…"`

A manifest may declare `"require": "bin:codex"` — the plugin exists only
when that tool is on `PATH`. The bar probes in one sweep, says so honestly
in Settings («needs 'codex' installed»), keeps re-probing while it is
missing, and brings the plugin back by itself the moment the tool appears.

## Visual components

The bar's look, ready to assemble — every piece takes the palette from
`K4.Tema` so a plugin lands looking native:

| Type | What it is |
|---|---|
| `K4.Etiqueta` | Text with the bar's defaults (white, Adwaita, 12px) |
| `K4.Glifo` | A Nerd Font glyph (find codepoints with `tools/glifos.py`) |
| `K4.Icono` | An `IconImage` ready to render application icons |
| `K4.IconoPlugin` | A plugin's own image, falling back to a glyph |
| `K4.Miniatura` | The live thumbnail of an open window, by address |
| `K4.Interruptor` | The bar's switch |
| `K4.Deslizador` | The bar's slider |
| `K4.Medidor` | A read-only bar: `valor` out of `maximo`, with the house track and easing |
| `K4.Baldosa` | Pressable card: hover lift, press sink |
| `K4.Boton` | Round one-glyph button |
| `K4.Aparicion` | Fade-in for views |
| `K4.Rodillo` | Scrollable column whose wheel works over hoverable rows |
| `K4.FocoInicial` | Grabs keyboard focus when a view opens |

`ejemplos/piezas/` is the runnable showcase of all of them.

## Plugin state that survives: `K4.Guardado`

For game saves, counters, anything that must outlive a restart. It owns a
JSON file under the plugin's own state directory:

```qml
property var guardado: K4.Guardado {
    plugin: "hello"
    onCargado: function (d) { self.visitas = d.visitas || 0 }
}

function apuntar() {
    guardado.guardar({ visitas: visitas })
}
```

Prefer it over raw `K4.Fichero` for plugin state: the path, the directory
and the load signal are handled for you.

## Processes: `K4.Process`

`K4.Process` wraps an external process and provides two output modes:

```qml
K4.Process {
    id: query
    command: ["python3", K4.Paths.guion("data.py")]
    running: abierto
    onSalida: function (text) { model = JSON.parse(text) }
    onLineaError: function (line) { console.warn(line) }
}
```

For one event per line:

```qml
K4.Process {
    command: ["my-command", "--watch"]
    porLineas: true
    running: true
    onLinea: function (line) { ... }
}
```

Properties include `command`, `running`, `workingDirectory`, `environment`,
`porLineas` and `entradaAbierta`. Signals are `arrancado`, `linea`, `salida`,
`lineaError` and `terminado(code)`. Stop a process that writes a file with
`parar()` (SIGINT), not a hard kill.

## Files and paths

`K4.Paths` keeps plugins independent from filesystem layout:

```qml
readonly property string statePath: K4.Paths.estado + "/hello.json"
K4.Fichero { id: state; path: statePath; blockLoading: true }

function save() {
    state.setText(JSON.stringify({ count: count }, null, 2))
}
```

- `K4.Paths.estado`: `~/.local/state/k4`, for persistent state.
- `K4.Paths.raiz`: the k4 installation root.
- `K4.Paths.guion(name)`: a file inside `tools/`.
- `K4.Paths.enRaiz(relative)`: any repository asset.

`K4.Fichero` provides `path`, `text()`, `setText()`, `blockLoading` and
`onLoaded`. Use it for small JSON/text files, not media assets.

## System and applications

`K4.Sistema` provides desktop actions:

```qml
K4.Sistema.abrir(path)
K4.Sistema.lanzar(["program", "--option"])
K4.Sistema.avisar("Title", "Details", false)
K4.Sistema.copiar("text")
const home = K4.Sistema.entorno("HOME")
```

`K4.Apps.lista` contains installed desktop entries; `K4.Apps.porId(id)` looks
one up and `K4.Apps.icono(name)` resolves its icon. `K4.Icono` is an
`IconImage` ready to render.

### Window thumbnails

`K4.Miniatura` paints what is inside another window, and keeps painting it —
it is live, not a photo taken when the panel opened. An Alt+Tab, a preview on hover: places where the title is not enough, because
three terminals are called the same and look nothing alike.

```qml
K4.Miniatura {
    width: 160; height: 100
    direccion: "0x5622613de2c0"      // the one `hyprctl clients` gives
}
```

You hand it the window's **address**, not the window: a plugin cannot talk to
the compositor — that is what services are for — but it does have the address,
which is what `hyprctl` returns and what you already use to focus a window.
Finding whose window it is happens inside.

If the window does not exist, or closes while you are looking at it, nothing
is painted. That is deliberate and there is no signal for it: whoever shows
the thumbnail already knows which windows they have, and a thumbnail that
shouts when its window goes is more annoying than a gap.

## Reading the machine

Live system data, one wrapper per source. Reading is free; the few write
operations are permission-gated (see the manifest permissions below):

| Type | Reads | Gated writes |
|---|---|---|
| `K4.Audio` | volume, mute | `ponerVolumen`, `alternarSilencio` → `audio` |
| `K4.Medios` | player, track, artwork | `alternarPausa`, `siguiente`… → `medios` |
| `K4.Red` | Wi-Fi and Bluetooth state | none — read-only, no exceptions |
| `K4.Escritorios` | Hyprland workspaces, and `lleno(screen)` — is something filling that screen? | — |
| `K4.Notificaciones` | notification count and recents | `limpiar` → `notificaciones` |
| `K4.Portapapeles` | clipboard history | reading is itself gated → `portapapeles` |
| `K4.Reloj` | the bar's clock | — |

## Sound: `K4.Sonido`

A short effect — `fuente` points at the audio file, `volumen` scales it.
Requires the `sonido` permission: a plugin that can make noise says so.

```qml
K4.Sonido {
    id: campana
    fuente: campana.delSistema("bell")
    volumen: 0.4
}
```

Then `campana.sonar()` plays it.
`delSistema(name)` resolves a desktop theme sound already installed on the
machine — `bell`, `message`, `complete`, `dialog-error` — so a plugin can
have sound without shipping audio files. Note it is a method **of the
object**, not of the type: `campana.delSistema(…)`, never
`K4.Sonido.delSistema(…)`, which fails silently inside the binding and
leaves you with no sound and no error. `listo` tells you whether it can
actually play.

## IPC, windows and shortcuts

Expose commands with `K4.Ipc`:

```qml
K4.Ipc {
    target: "k4.hello"
    function toggle(): void { self.abierto = !self.abierto }
}
```

Call it from Hyprland with:

```sh
quickshell ipc -p ~/.config/quickshell/k4/shell.qml call k4.hello toggle
```

The target is `k4.<id>`. Two house plugins carry older names — `k4.term`
(terminal) and `k4.theme` (hyprtheme) — kept for the muscle memory that
already types them; anything new follows the convention.

- `K4.Ventana`: a full-screen `wlr-layer-shell` surface that does not reserve
  layout space. `capa` picks the level: `"encima"` above everything (the
  island included), `"normal"` above windows and below the island, and
  `"fondo"` **below the windows** — what an animated wallpaper needs. It
  lands on `Bottom`, not `Background`: wallpaper daemons live on
  `Background`, and within one layer the newest surface wins, so relaunching
  swaybg would silently cover whatever you drew. Give a background window a 0×0
  `zonaActiva`, or its `null` mask swallows every click on the desktop.
- `K4.PorPantalla`: one instance per monitor.
- `K4.Cargador`: a `LazyLoader` for expensive views or windows.
- `K4.Autenticacion`: PAM authentication state and signals.
- `K4.BloqueoSesion` and `K4.SuperficieBloqueo`: the real `ext-session-lock`
  and its per-output surface.
- `K4.MenuBandeja`: an application tray menu.

## Pill indicators

Plugins can register a small indicator without editing `shell.qml`:

```qml
Component.onCompleted: K4.Pildora.registrar(
    "hello.status", "ready", 0xF05A1, "#30d158", 80, true)

Connections {
    target: K4.Pildora
    function onInvocado(id) {
        if (id === "hello.status") self.abierto = true
    }
}
```

Available operations are `registrar(id, text, glyph, color, order, visible)`,
`actualizar(id, fields)`, `quitar(id)` and `quitarDe(owner)`. IDs must start with
the plugin ID (`hello.`). The host removes a plugin's indicators when it is
disabled.

## Your settings, in Settings

Plugins contribute rows to the bar's Settings screen with `K4.Ajustes`: the
plugin keeps the values, the bar asks for them (`valores`) and notifies
(`cambiado`). A switch per option is the default; `tipo` unlocks the rest:

- `"eleccion"`: chips with your own `alternativas: [{ codigo, nombre }]`;
  `cambiado` delivers the chosen `codigo`.
- `"texto"`: a free-text field — a URL, a model name, an API key. `pista`
  is the empty-field hint and `secreto: true` masks the value once typing
  stops. The value arrives on confirm (Enter or focus out), not per
  keystroke.

With these, a plugin that talks to a service, an AI or a CLI configures
itself in Settings like everything else.

## Your pages in Settings: `K4.Pagina`

A whole page, not a row of options. The plugin that knows the work ships
the screen for it: it renders inside the Settings window with the same
sidebar, the same search and the same scroll as every native page, and it
leaves with its author — a disabled plugin contributes no pages, so
nothing renders a dead engine's knobs.

```qml
K4.Pagina {
    plugin: "hola"
    name: "gretings"          // unique within your plugin
    titulo: "Greetings"       // sidebar title
    padre: "Display"          // optional: nest under a family
    glifo: 0xF02FC
    desc: "How this plugin greets the desktop"
    claves: ["hello", "salute"]
    componente: Component { MiPagina {} }
}
```

- `padre` is the family to nest under, by its title — a native family
  («Display») or another contributed page's `titulo`. Empty means a
  top-level section of your own. Titles are the sidebar's ids: pick one
  no other section uses.
- `claves` are search keys, read exactly like a native group's.
- `componente` is instantiated only while its page is on screen, in your
  plugin's own context — the same arrangement as `K4.Plugin.view`. Root
  it in a layout that reports `implicitHeight` and the window sizes and
  scrolls it for you.
- External plugins declare the `"paginas"` permission: injecting pages
  into Settings is UI power, and it shows on the consent card.

The bar's own plugins use the same door — the theme engine ships the
Display family's Colour, Windows and Effects pages this way.

## Your blocks in the control centre: `K4.Card`

A block of the centre, shipped by the plugin that does the work. It
renders among the native toggles/media/shortcuts wherever the stored
order says, with the same width and the same editor: the user reorders
and hides it in Settings → Control centre like any native block, and it
disappears with its author.

```qml
K4.Card {
    plugin: "correo"
    name: "unread"            // unique within your plugin
    titulo: "Mail"
    glifo: 0xF01EE
    desc: "One line for the editor row"
    alto: 64                  // px the card occupies
    component: Component { MiFila {} }
}
```

- The centre knows the card as `"<plugin>.<name>"`.
- `alto` is fixed, like the native blocks' own heights: the centre sizes
  itself from it and hands the card exactly that room — fill it, don't
  fight it.
- `component` is instantiated only while the centre is open on its
  controls tab, in your plugin's own context.
- Visibility is the user's, not yours: the editor's eye hides the card
  (Settings owns a card's visibility; the native blocks' own switches
  are the same deal).
- Declare the `centro` surface in the manifest to have the validator
  vouch for it. `ejemplos/worldclock/` ships a working card.

## Your results in the launcher: `K4.Lanzador`

Answer the launcher's queries whenever you can — a slow source blocks
nobody. Your results appear below the system's applications:

```qml
K4.Lanzador {
    plugin: "hola"
    onBuscando: function (texto) {
        resultados = texto.length < 2 ? []
            : [{ id: "abrir", titulo: "Open Hello", desc: "…" }]
    }
    onElegido: function (id) { self.abierto = true }
}
```

## The island as a stage

- `K4.Tema.tintar(id, color, strength, durationMs)` tints the bar's neutral
  scaffold — island, surfaces, tracks — and everything painted with the
  theme recolors itself reactively. Ink and semantic colors stay untouched
  so text stays readable; strength is capped at 0.45 by the host, and
  `K4.Tema.destintar(id)` — or disabling the plugin — reverts it.
- `K4.Isla.efecto(id, name, strength)` asks for a physical gesture:
  `"sacudida"` (a hit), `"empujon"` (something heavy lands), `"tiron"`
  (something pulls, like a fish on the line). The host animates and
  rate-limits to one gesture per half second.
- `K4.Isla.rect` is the island's real screen geometry (`{ x, y, ancho,
  alto }`); with a transparent `K4.Ventana` above everything you can draw
  outside the island — a waving hand, a pet peeking over the edge.
- `K4.Isla.aLaVista` says whether anyone can see the island right now —
  false while it is retracted in *Hidden* space mode, while a system dialog
  has it out of the way, and on a monitor whose bar is not
  showing. **An animation that never ends must ask this**, because in Qt
  Quick an animation does not stop when its item stops being visible; see
  [PLUGINS.md](PLUGINS.md#an-animation-nobody-sees-still-runs).
- The bar's edge and alignment belong to the user (Settings: top/bottom,
  left/center/right). `K4.Isla.posicion` tells you the edge; and
  `K4.Isla.colocar(id, fraction, durationMs)` slides the island along it
  for the duration of a scene — a dodge, a paddle, stepping aside — and it
  springs back on timeout, `soltar(id)`, or disable.
- **The hover band**: offering a view while the mouse rests on the pill is
  not a separate API — bind `active` to `K4.Isla.raton` and pick a
  priority by who you want to beat: 1–39 under the clock, 51–54 over the
  clock and under the player, 56–58 over the player too. Leaving is the
  binding's job — `raton` clears a moment after the mouse goes and the
  stage returns to the pill; `closeOnHoverExit` is for summoned views.
  `ejemplos/hoverpeek/` ships one working.

`ejemplos/efectos/` has every piece working, hand included.

## Current boundaries

Plugin loading is dynamic and isolated: each plugin is created on its own, a
failure is recorded with its error, and the rest start. Disabled means not
instantiated. Third-party plugins load from `~/.config/k4/plugins/<id>/`.

What that does **not** mean is a sandbox. QML runs inside the bar's process and
a loaded plugin can do whatever the bar can do. The declared permissions are
informed consent — you see them before enabling — plus a static analysis that
turns carelessness and simple deception into an installation error. Installing
a plugin is trusting its author.

Two doors stay shut on purpose: connecting to networks and pairing Bluetooth
devices are read-only for plugins, with no permission that opens them.

The full guide, kept current by `tools/api.py` and `tools/guia.py`, is
`docs/PLUGINS.md`. New dependencies still go in `dependencias.tsv`.
