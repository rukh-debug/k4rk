# k4 on Nix

k4 runs on Nix without ever touching `./install`: the flake ships the bar,
its whole environment, and the Hyprland integration. This page is for the
Nix path; the [README](../README.md) is still the front door.

```sh
nix run github:rukh-debug/k4rk        # the bar, right now
nix develop                          # the development shell, on a checkout
```

---

## Why a mirror: how k4 runs under Nix

k4 **writes into its own directory**: the `externos` symlink that brings
user plugins in, the `recargas/` folders hot reload creates. The Nix store
is read-only, so the package cannot run straight from `/nix/store`.

What the package does instead:

```
/nix/store/…-k4  ──(first run, or after an update)──▶  ~/.local/share/k4/code
                                                               │
                                              exec quickshell ─┘
```

The launcher (`bin/k4`) materializes a writable copy at
`~/.local/share/k4/code` and starts from there. A marker file
(`.k4-origen`) records which store path it came from: while that does not
change, starting the bar is one `stat`. Updating is `nix flake update` —
the next launch rebuilds the mirror.

Everything else lives outside the code, as it always has:
`~/.config/k4/config.json` (shareable settings), `~/.local/state/k4` (private state), `~/.config/k4/plugins`
(user plugins). The mirror is only the code.

**The built-in updater is out of the picture.** There is no `.git` in the
mirror, on purpose: Settings offering a `git pull` on a Nix-managed copy
would be fighting itself. Settings reports `no-git` and updates
come through the flake.

## What the environment carries

The launcher exports everything the bar needs, so `nix run` behaves the
same inside a Hyprland session on NixOS as on any other distro:

- **PATH** with every helper from [`dependencies.tsv`](../dependencies.tsv):
  grim, slurp, swaybg, ffmpeg, imagemagick, zenity,
  wl-clipboard, fd, pactl, wpctl, nmcli, bluetoothctl, notify-send,
  xdg-open, hyprctl, python3, git, curl… The optional ones (yay,
  nvidia-smi, claude, codex) stay out, exactly as `./install` leaves them
  without `--optional`.
- **QtMultimedia**, which nixpkgs' quickshell does not pull in and media
  playback and video wallpapers need — with the ffmpeg backend forced.
- **The two fonts as ever**, Adwaita Sans and MesloLGS Nerd Font Mono,
  through a `FONTCONFIG_FILE` that includes the system configuration:
  your other fonts keep resolving as before.
- **The `K4` QML module** (`api/`), which the launcher puts on the import
  path, same as on Arch.

## Home Manager

For Control Center power profiles and city-based night light, see
[Power & display](POWER-DISPLAY.md). Enable `services.power-profiles-daemon`
in NixOS and `programs.k4.nightLight.enable` in Home Manager. The latter manages
one neutral-starting hyprsunset backend bound to the Hyprland session; k4 owns
the live schedule. The package includes Astral for offline solar calculations.

```nix
# flake.nix
inputs.k4.url = "github:rukh-debug/k4rk";
inputs.k4.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
# your configuration
imports = [ inputs.k4.homeManagerModules.k4 ];

programs.k4.enable = true;
```

For persistent settings in **Settings → Display → Monitor**, enable:

```nix
programs.k4.monitors.enable = true;
```

This requires Home Manager-managed Lua Hyprland. It appends a monitor-only hook
after the normal output defaults, independently of `hyprland.hookIntoConfig`.
Only confirmed changes are saved, in `$XDG_STATE_HOME/k4/monitors/profile.json`; without
this option the page applies session-only changes. See [Monitor settings](MONITORS.md)
for the apply/revert contract, supported controls, and recovery behavior.

That gives you the package on PATH and the Hyprland integration written
from the repo's own templates (`hypr/k4.conf` and `hypr/k4.lua`),
with three changes — autostart calls the store wrapper (on a cold start
the mirror does not exist yet; the wrapper creates it), IPC shortcuts
target the mirror's `shell.qml` (the running instance, which is what
`quickshell ipc -p` must point at), and `quickshell` gets an absolute
path.

If Home Manager manages your Hyprland, the `source` line (or the
`require`, on the Lua flavor) is added for you. If you write your
`hyprland.conf` by hand, add the line yourself:

```ini
source = ~/.config/hypr/k4.conf
```

Options:

| Option | Default | Effect |
|---|---|---|
| `programs.k4.enable` | `false` | Install k4 and write the integration. |
| `programs.k4.package` | `pkgs.k4` | The package (the overlay, or another). |
| `programs.k4.hyprland.writeConfig` | `true` | Write `k4.conf` and `k4.lua`. |
| `programs.k4.hyprland.hookIntoConfig` | `true` | Add the `source`/`require` when HM manages Hyprland. |
| `programs.k4.hyprland.template` | `null` | Your own Hyprland template instead of the package's. Same substitutions; rendered as the flavor-appropriate file. The right home for a host's key layout — the Lua bind API accumulates, so collisions are removed in the template, and that template is yours, not upstream's. |

## NixOS

```nix
inputs.k4.url = "github:rukh-debug/k4rk";
```

```nix
imports = [ inputs.k4.nixosModules.k4 ];
programs.k4.enable = true;
```

Adds the package system-wide and the two fonts to `fonts.packages` — for
everything else that asks for “Adwaita Sans”. Autostart remains your
session's business; the Home Manager module is the one that knows how to
hook it into Hyprland.

## Overlay

```nix
nixpkgs.overlays = [ inputs.k4.overlays.default ];
environment.systemPackages = [ pkgs.k4 ];   # or home.packages
```

## Development

```sh
nix develop
```

The flake's shell against a checkout: quickshell with QtMultimedia, the
helpers, Python with numpy/Pillow for image work and fontTools for
`tools/glyphs.py`, the fonts, and `QML_IMPORT_PATH` already pointing
at `./api`. The README's validators run as-is:

```sh
python3 tools/plugins.py && python3 tools/api.py && python3 tools/glyphs.py
```

## Notes

- **User plugins work the same**: `python3 tools/plugins.py --install <url>
  --commit <sha>` writes to `~/.config/k4/plugins` and the mirror's
  `externos` link is already in place. Hot reload (`quickshell ipc -p
  ~/.local/share/k4/code/shell.qml call k4 pluginReload <id>`) does too.
- **IPC**: always point at the mirror's `shell.qml`,
  `~/.local/share/k4/code/shell.qml` — not the store's.
- **Non-Nix machines**: none of this changes the `./install` path; two
  doors into the same room.
