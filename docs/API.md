# k4 public API

This is the public surface available to plugins. The API lives in `api/K4/`; the
source files contain additional implementation notes.

## Imports

A plugin imports Qt and k4:

```qml
import QtQuick
import K4 as K4
```

Start the host with `launch` (or the Nix `k4` wrapper). It adds `api/` to
`QML_IMPORT_PATH`; launching
`quickshell -p shell.qml` directly will not resolve `import K4`.

Qt (`QtQuick`, `QtMultimedia`, `Timer`, animations, and so on) is the portable
layer. Quickshell and Wayland should stay behind a `K4` API type whenever an
equivalent exists.

## Native markdown

`K4.MarkdownView` renders selectable CommonMark/GFM prose, headings, lists,
task lists, quotes, links, strikethrough, tables and highlighted fenced code.
Set its `width`; its implicit height follows the document. Wide code and tables
scroll horizontally. Code blocks expose a copy action; rendering never executes
code or fetches remote images (images are explicit links).

| Member | Meaning |
|---|---|
| `text` | Markdown source; default empty |
| `streaming` | Batch render updates at 100ms while streaming; default false |
| `color` | Prose color; defaults to `K4.Tema.tinta` |
| `fontSize` | Prose size in pixels; default 14 |
| `linkActivated(url)` | User activated an HTTP, HTTPS or mailto link; caller handles opening |
| `copyRequested(text)` | User requested the original text of a code block; caller handles copying |
| `selectionStarted()` | Nonempty text selection; a following chat should pause automatic scrolling |

One internal JSON-lines worker uses Mistune 3 and Pygments, pinned through the
Nix lockfile and declared in `dependencias.tsv`. Rendering runs outside the UI
thread, uses a bounded cache, and preserves unchanged block delegates. If the
worker fails, the view shows selectable plain source. Selection is per rendered
block. Math and diagrams remain source text/code. Internal underscored members
and `api/K4/markdown/` are implementation details.

## System telemetry

`K4.SystemMonitor` is a read-only singleton backed by the host sampler. It needs
no permission. Plugins do not read procfs or launch hardware tools themselves.

| Member | Meaning |
|---|---|
| `available` | The host telemetry bridge is installed |
| `ready` | CPU has two valid samples and memory is available |
| `cpuPercent`, `memoryPercent` | 0–100; `-1` when unavailable or warming up |
| `cpuTemperature` | Celsius; `0` means unavailable |
| `memoryUsed`, `memoryTotal` | GiB; total `0` means unavailable; used is total minus available |
| `download`, `upload` | Bytes/second; `-1` means no valid interval |
| `interfaceName` | The measured default-route interface, or empty; not an internet-speed estimate |
| `view` | Host-owned detailed monitor `Component`, or null without a host; use as a Loader's `sourceComponent` |
| `sample(owner, active, detailed)` | Acquire/update a sampling lease. `detailed` also enables the cheap sampler. Release with both flags false |
| `rate(bytes)` | B/s, KiB/s or MiB/s text; `—` for unavailable |
| `compactRate(bytes)` | At most four characters with binary B/K/M/G/T/P scaling. Promotes when rounding would reach 1000; uses one decimal below 10 for M and larger units, whole numbers otherwise. Caps at `≥1P` (one PiB/s). `—` for negative or non-finite readings |
| `temperature(value)` | Celsius text or `—` |

Use a unique owner string per concurrent consumer. Release leases when disabled
or destroyed and reacquire when `available` becomes true. Cheap samples refresh
every second; histories and process/GPU readings approximately every two seconds;
filesystem capacity every thirty seconds while detailed sampling is active.
The host view includes CPU/Memory process sorting and identity-checked SIGTERM
actions, with the result displayed in the view. Process CPU uses 100% per logical
CPU; the summary CPU percentage is normalized across all logical CPUs.

## Plugin contract

`K4Plugin` is the root object of a module:

| Property | Meaning |
|---|---|
| `name` | Stable, unique plugin ID |
| `title` | Human-readable name |
| `habilitado` | Persistent user permission |
| `active` | Requests presentation right now, in the main island or an independent island |
| `priority` | Main-island arbitration priority — against the resting views and the transients; among main-island summoned views the one just opened supersedes the previous (the host closes it). Independent islands do not compete in this arbitration |
| `transitorio` | View that appears unasked and expires on its own; in the main island it closes when another plugin takes over. Independent transients keep their own lifetime |
| `islandWidth`, `islandHeight` | Requested island size. For `colocable` surfaces, per-dimension user overrides in Settings → Popups & Layout take precedence in both hosts; Auto follows these live requests. The host fits the result to the screen. Size the view from its actual parent, not these requests |
| `view` | Component rendered by the host |
| `viewLoaded` | Keep the size while the view closes |
| `grabKeyboard` | Exclusive keyboard focus |
| `tecladoOpcional` | On-demand keyboard focus |
| `tecladoAlPasar` | Exclusive keyboard focus only while the pointer is over the island (for games) |
| `closeOnHoverExit` | Enable hover-exit timeout |
| `colocable` | Your surface is a summoned view: it gets a card in Settings → Popups & Layout, where the user chooses its size, edge and alignment. Only what OPENS gets placed — the pill's wings, transients and indicators do not |
| `independentIsland` | Boolean, default `false`. Present `view` in a separate host-managed island while leaving the main island and other views open. Settings → Popups & Layout can override this default for any placeable surface. Applies to the plugin's `view`, not its own `K4.Ventana` windows; no extra manifest surface or permission is needed |
| `summonCommand` | The IPC call that opens the surface — everything after `call` (`"k4.launcher toggle"`), which the copy button on the expanded popup card hands out as a full command line. Only the plugin can say it for sure: the `k4.<id>` target and the `toggle` verb are conventions, and conventions break (the terminal lives at `k4.term`, and its toggle is `island`). Empty (default) hides the button |

### Independent island presentation

`K4.Plugin.independentIsland` is the plugin's default. The host persists the
user's explicit true/false override in `independentIslands`, independently of
`islandPlacements`. Choosing **Follow bar** changes the preferred position,
not the presentation mode. Disabling the switch restores main-island arbitration
and replacement behavior. Hyprland Submap defaults to independent presentation.

An independent island always opens separately. It tries its configured position
first, then corners clockwise: top-left, top-right, bottom-right, bottom-left.
From a non-corner position, the first corner is the next one along that edge
(top → top-right, right → bottom-right, bottom → bottom-left, left → top-left).
Allocation avoids the main island and other independent islands on the same
monitor, including notification popups, with clearance for the wings. If no
corner is free, the least-overlapping corner wins; equal overlaps keep clockwise
order. Existing independent windows allocate before newer ones. A free allocated
position stays stable until it is obstructed, the requested placement/size changes,
or the window closes. Moving between positions does not recreate the view.

The host uses the requested monitor or the focused monitor at opening. Summoned
independent views retain cross-monitor dismissal. `active`, `viewLoaded`, size,
background-tap handling, `closeOnHoverExit`/`hoverTimedOut`, and keyboard flags
still apply. The newest eligible independent view receives exclusive keyboard
focus; the main island yields while it holds it. The newest independent view
requesting outside-click dismissal on a monitor catches outside taps, with holes
for other islands so they remain interactive. Independent islands do not dim the
desktop. `close()` remains the plugin's responsibility.

`K4.Isla` describes the **main** island, not an independent view's geometry or
occupancy. Independent views should use their own item's dimensions, focus and
hover state. Native notifications retain their existing main-island-when-idle,
separate-when-busy policy and notification corner setting, but share allocation
with independent plugin islands.

### Host verbs

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

A manifest may declare `"require": "bin:yt-dlp"` — the plugin exists only
when that tool is on `PATH`. The bar probes in one sweep, says so honestly
in Settings («needs 'yt-dlp' installed»), keeps re-probing while it is
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
| `K4.ActionButton` | Compact text action or controlled choice chip |
| `K4.TextField` | Single-line editor with shared sizing, selection and focus styling |
| `K4.Aparicion` | Fade-in for views |
| `K4.Rodillo` | Scrollable column whose wheel works over hoverable rows |
| `K4.FocoInicial` | Grabs keyboard focus when a view opens |

`ejemplos/piezas/` is the runnable showcase of all of them.

### Controls, keyboard and focus

`K4.ActionButton` inherits Qt Quick Controls `AbstractButton`: set `text`,
handle `clicked()`, and use inherited `enabled` to disable interaction.
Its additional `selected: bool` property defaults to false and is controlled by
the caller; activation does not change it. Its default height is 32 logical px.

`K4.TextField` inherits Qt Quick Controls `TextField` and defaults to 210 × 32
logical px. It supports `text`, `placeholderText`, `validator`, `echoMode`,
`accepted()` and `editingFinished()`. The caller supplies a persistent visible
label and `Accessible.name`, and owns validation and commit/cancel policy.
Use password echo mode for secrets and keep credential drafts transient.

`K4.Boton`, pressable `K4.Baldosa`, and `K4.Interruptor` support Tab focus,
Enter/Space activation and a visible focus outline. Supply `Accessible.name`
for icon actions, navigation cards and switches. Their existing signals remain
owner-controlled; a switch emits `alternado()` without changing `marcado`.
`enabled: false` prevents pointer and keyboard interaction. `Boton.activo`
also controls its default enabled state.

`K4.Deslizador` supports arrows to change by `paso`, Home/End for bounds, and
accessible increase/decrease actions. Read-only `dragging` reports pointer
manipulation. An empty `etiqueta` hides its heading/value row;
a labelled slider is 60 px high (32 px without a label), with a thick filled
track and an inset grip. Set `Accessible.name` explicitly when hiding
the heading. Pointer feedback is immediate while dragging; external updates
ease into place. Quantization starts at `desde` and respects both bounds.

`K4.Rodillo` also reveals focused descendant controls during keyboard traversal
and accepts pixel-based trackpad scrolling.

### Interaction sounds: `K4.Feedback`

The host preloads bundled WAV samples for short, low-latency interaction cues.
`K4.Boton`, `K4.ActionButton`, pressable `K4.Baldosa`, and `K4.Interruptor`
request a click on activation, including keyboard and accessible actions.
`K4.Deslizador` requests a quieter tick only when user input requests a changed
value; bound/background value updates and attempts beyond its bounds are silent.
Disabled controls do not request feedback. A child button inside a card produces
only its own cue.

For custom controls, the singleton provides two argument-free methods:

| Method | Behavior |
|---|---|
| `K4.Feedback.click()` | Request the standard button click |
| `K4.Feedback.tick()` | Request a quieter adjustment tick, limited to one per 80 ms |

Call these only for user activation or adjustment, never from polling, hover,
or property-change handlers. Shared controls already call them; do not add a
second call in their action handlers. These fixed UI cues require no plugin
permission. Arbitrary samples still use `K4.Sonido` and its permission.

**Settings → Island → Interaction sounds** controls `uiSoundsEnabled` (default
true) and `uiSoundVolume` (0–100%, default 35%). Gain is relative to system
volume; ticks use 55% of the click gain. The service follows the default audio
output and stays silent while muted, at zero volume, without an output, or
before settings/samples are ready. Suppressed ticks are dropped, never queued.
There is no desktop-wide input listener: feedback covers k4 controls.

From the repository root, run the pointer, keyboard, controlled-state and
focus-scrolling regression tests with Quickshell's static QML modules loaded:

```sh
QML_IMPORT_PATH="$PWD/api${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  QT_QPA_PLATFORM=offscreen quickshell -p tools/ui-controls-test.qml
```

```qml
K4.ActionButton {
    text: "Retry"
    enabled: !requestPending
    onClicked: retryRequest()
}
K4.Interruptor {
    Accessible.name: "Enable notifications"
    marcado: notificationsEnabled
    onAlternado: setNotificationsEnabled(!notificationsEnabled)
}
```

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

The target is `k4.<id>`. One house plugin carries an older name — `k4.term`
(terminal) — kept for the muscle memory that already types it; anything new
follows the convention.

Declare the call your surface answers in `summonCommand` (everything after
`call`): the popup card's copy button hands out the whole command line,
prefix included, and only the plugin knows both halves for sure — the target
and the verb are yours, the path belongs to the running instance.

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

Available operations are `registrar(id, text, glyph, color, order, visible, slots)`,
`actualizar(id, fields)`, `quitar(id)` and `quitarDe(owner)`. IDs must start with
the plugin ID (`hello.`). The host removes a plugin's indicators when it is
disabled.

The host sizes all indicator glyphs using **Settings → Island → Indicator icon
size** (8–20 px, default 14 px). The setting applies to the folded pill and the
clock/player hover views; label and numeric-slot text keep their existing size.

The optional seventh argument, `slots`, is an array of numeric text slots:

```qml
K4.Pildora.registrar("hello.load", "9%", 0xF061A, "#30d158", 80, true,
    [{ text: "9%", samples: ["100%"] }])
K4.Pildora.actualizar("hello.load", {
    texto: "10%", slots: [{ text: "10%", samples: ["100%"] }]
})
```

Each slot has `text` (the live string), `samples` (an array describing the
widest possible strings), and an optional stationary `prefix` such as `↓` or
`↑`. A nonempty array replaces the ordinary text visually; keep `texto` as its
plain-text equivalent. Omitted or empty `slots` retain ordinary auto-sizing.
Updates replace the whole slots array, so retain samples and prefixes when
changing text.

Slots with a prefix are left-aligned so the value sits directly beside its
stationary prefix; slots without a prefix are right-aligned. Both use tabular
digits in the current shell font and reserve the widest sample independently
of the live reading. Measurements allow for
fonts without tabular digits and always fit the unavailable marker `—`.
Samples and prefixes should stay constant across value updates; changing them
or the shell font intentionally recalculates the reservation. Values exceeding
the declared samples are elided rather than growing the island. Multiple slots
have a fixed 3 px gap, and the same measurements size all three pill views and
their host estimates.

For a compact network rate, samples covering all formatter outputs are
`["999B", "999K", "999M", "999G", "999T", "9.9M", "9.9G", "9.9T", "1.0P", "≥1P"]`.
Use separate slots with `prefix: "↓"` and `prefix: "↑"` so download changes
cannot move the upload arrow or value.

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
    detailTitle: "Mail"       // optional drill-down header
    detail: Component { MailDetails {} }
}
```

- The centre knows the card as `"<plugin>.<name>"`.
- `alto` is fixed, like the native blocks' own heights: the centre sizes
  itself from it and hands the card exactly that room — fill it, don't
  fight it.
- `component` is instantiated only while the centre is open on its
  controls tab, in your plugin's own context.
- `detail` is optional. Call `openDetail()` from the card to host that
  component inside the Control Centre. `detailTitle` labels the shared header;
  the host supplies Back, Escape navigation and cleanup if the plugin unloads.
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
- `K4.Tema.tinteDueno` and `K4.Tema.tinteColor` expose the current tint when
  a plugin needs to follow a native host-owned palette without sampling or
  owning it itself.
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

## Terminal access and providers

`K4.Terminal` routes `ejecutar(script)` to the registered island provider when
available, otherwise to a window. `abrir(path)` always opens a window.
`cual` is the selected window executable, `enLaIsla` reports whether scripts
will run in the island, and `cierre` is the optional shell fragment that keeps
a command window open. Launching processes requires `procesos`.

The terminal provider uses the following host adapter instead of importing
host services:

| Member | Contract |
|---|---|
| `islandAvailable` | An island backend is available; Python is bundled with the Nix package |
| `nativeIslandAvailable`, `nativeWindowAvailable` | Availability of k4term-isla and the selected k4term window terminal, respectively |
| `registerIsland(callback)` | Register the provider's script runner; pass `null` on destruction |
| `refreshBackends()` | Recheck binaries through the host's dependency service |
| `windowCommand(path)`, `scriptCommand(script)` | Return argument arrays for a window; executing them requires `procesos` |
| `themePath` | Published terminal theme file; reading it requires `ficheros` |
| `focusedPid` | Focused window's PID as a string, or an empty string |
| `connecting`, `connectionStartedAt`, `connectionTint` | Shared connection destination, start time in milliseconds, and tint |
| `takeConnectionPassword()` | Consume and clear the pending connection password; keep it only on the intended session |
| `markConnectionStarted()` | Record when the connection command actually starts |
| `connectionFinished()` | Clear the pending connection indicator and password |
| `connectionEnded(destination)` | Notify the host that the session left a server |
| `trackNotice(title, pid)`, `clearNotice(title)` | Route and clear the terminal's own attention notifications; clearing requires `notificaciones` |

Backend selection is fixed for each session. Installing a native backend
affects new sessions only. Hiding a terminal preserves its PTY; closing a tab,
disabling the plugin, or stopping the bar terminates the owned session.
Native session transfer requires both native binaries and a native session.

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
