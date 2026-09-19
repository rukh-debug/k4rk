# Power & display

Control Center has separate **Power mode** and **Night light** cards, each
opening its own native detail page. Their shared **Power & display** row can
be hidden or reordered in Settings' Control Center editor. Keyboard navigation,
Escape/back and slider interaction follow the other native detail pages.

## Brightness

Quick controls place **Sound** and **Brightness** side by side below Wi-Fi and
Bluetooth. Settings can hide either tile independently (`panelTileBrightness`
controls brightness). The display picker selects one screen at a time; the
slider and percentage always describe that screen. Arrow keys adjust by 1%;
Home/End select 1%/100%. The minimum avoids turning off the laptop backlight.

Laptop screens use `brightnessctl`; external monitors use `ddcutil` and the
monitor's hardware brightness control (DDC/CI VCP 0x10). Both tools are bundled
in the Nix package. Enable DDC/CI in the external monitor's on-screen menu.
On NixOS, system access also needs:

```nix
hardware.i2c.enable = true;
users.users.YOUR_USER.extraGroups = [ "i2c" ];
```

Rebuild the system and log in again for group membership to take effect.
On other systems, load `i2c-dev` and grant your session read/write access to
the monitor's `/dev/i2c-*` device using the distribution's udev rules.
The UI explains missing tools, permissions, unsupported connections and
unresponsive monitors. Hover the status line to read a truncated message.

Displays are discovered through Linux backlight and DRM connector sysfs.
DDC targets are keyed by EDID and connector; the I²C bus is resolved afresh for
each operation, so a reconnect cannot redirect a queued write to a different
monitor. Docks that do not expose a DRM DDC adapter are reported as unavailable.
Selection is retained while the bar runs, falling back to an available display
on disconnect. Startup prefers the laptop backlight.

Dragging updates the UI immediately and coalesces hardware writes. Readback
confirms the applied percentage. Hardware-key and monitor-menu changes are
polled every two seconds while the card is shown; discovery repeats every 30
seconds and after monitor hotplug events. Brightness is owned by the hardware,
not saved or reapplied by k4 on startup. Night-light color temperature is separate.

## Power profiles

Enable the system's `power-profiles-daemon` service. On NixOS:

```nix
services.power-profiles-daemon.enable = true;
```

The page offers Power saver, Balanced and Performance. Unsupported profiles are
disabled; lack of a Performance profile does not disable the other two. The
daemon owns profile persistence. k4 subscribes to Quickshell's native profile
signals, writes with `powerprofilesctl`, and confirms the daemon's actual state
over D-Bus before displaying a successful selection. Application holds and
performance degradation appear below the selector.

## Night light

Use **hyprsunset 0.4 or newer**, with one instance per Hyprland session. k4 owns
the schedule and preferences; hyprsunset applies temperature changes through
its IPC socket. Do not configure a second schedule in hyprsunset or run another
color-temperature controller alongside it. Gamma brightness is not changed.

Home Manager can manage the backend:

```nix
programs.k4.nightLight.enable = true;
```

This starts hyprsunset neutral under `hyprland-session.target`, independently
of bar reloads. Other installations should autostart `hyprsunset --identity`
in their Hyprland session, with no timed profiles in its configuration.

Night light initially stays disabled. Enable it for manual operation, or select
**Sunset to sunrise**, search for a city and choose a result. City search uses
Open-Meteo's geocoding API (GeoNames data). Coordinates and timezone are saved;
Astral calculates solar events locally, so scheduling continues offline.
The UI displays event times in the system timezone.

Temperature ranges from 2500 to 6500 K, defaulting to 4000 K. Scheduled changes
fade over 15 minutes centered on sunrise/sunset. Turning the feature off uses
hyprsunset's identity transform rather than approximating neutral with a
temperature. Manual changes apply immediately after a short slider debounce.

In solar mode, **Pause until sunrise** / **Turn on until sunset** temporarily
override the schedule. Overrides have absolute expiry timestamps, survive bar
restarts, and can be cancelled with **Resume schedule**. At polar locations,
the sun's position determines day/night and overrides expire after 24 hours
when no nearby solar boundary exists.

The service reconciles at startup, after edits, on opening the page, and every
30 seconds while enabled (60 seconds while disabled). A resume, clock jump or
backend restart therefore recovers within that interval. The schedule is
wall-clock-based: restarting during a fade resumes at the current point. k4
must be running to advance the schedule; the independent backend retains its
last applied state while k4 is stopped. Missing or failed backends are reported
separately from saved preferences, and IPC writes are read back for confirmation.

Shared settings live in `services/Settings.qml`: `panelShowPowerDisplay`,
`nightLightEnabled`, `nightLightTemperature`, `nightLightMode` (`manual` or
`solar`), `nightLightLocation`, and `nightLightOverride`.

## IPC

Use the running shell's path with `quickshell ipc -p … call`:

| Target | Verb | Behavior |
|---|---|---|
| `k4.panel` | `powerMode` | Open the Power mode detail page |
| `k4.panel` | `nightLight` | Open the Night light detail page |
| `k4.powerMode` | `status` | JSON with confirmed profile, capabilities, pending state and errors |
| `k4.powerMode` | `set <profile>` | Request `power-saver`, `balanced` or `performance`; inspect `status` for confirmation |
| `k4.nightLight` | `status` | JSON with confirmed backend state and computed schedule |
| `k4.nightLight` | `refresh` | Reconcile current preferences and backend state |
| `k4.nightLight` | `enable`, `disable`, `toggle` | Change and save the master switch |
| `k4.brightness` | `status` | JSON with displays, selection, displayed value, busy state and errors |
| `k4.brightness` | `refresh` | Rediscover displays and read hardware brightness |
| `k4.brightness` | `select <id>` | Select a display using its ID from `status` |
| `k4.brightness` | `set <percent>` | Request 1–100% brightness for the selected display |

These are native host services, not plugin API types.

## Verification

`python3 -B tools/test_brightness.py` checks device discovery, reconnect identity,
brightness scaling, permissions, timeouts and confirmed hardware writes using
fake sysfs and commands. It also runs as `checks.brightness`.
`nix develop --command python3 -B tools/test_brightness_ui.py` tests all tile
visibility combinations at 640, 780 and 1100 pixels, slider alignment, keyboard
and pointer interaction, display selection, coalesced writes and error recovery.
The QML tests use fake brightness hardware and do not adjust your displays.

`python3 -B tools/test_power_display.py` (with Astral installed) checks day/night,
solar fades, overrides, DST/date-line cases, polar locations, backend failures
and confirmed writes. The Nix flake includes this as `checks.power-display`.
Check the menu layout with a screenshot, but check warmth on the physical
display: hyprsunset's transformation is not included in screen captures.
