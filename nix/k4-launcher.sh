#!/bin/sh
#  k4 launcher for Nix.
#
#  Why this exists: k4 is a program that writes into its own checkout — the
#  `externos` symlink that brings user plugins in, the `recargas/` folders
#  that hot-reload creates — and the Nix store is read-only. So the store
#  keeps the code and the launcher materializes a writable copy the first
#  time it runs, refreshing it whenever the store path (and thus the flake
#  input) changes.
#
#      store  →  ~/.local/share/k4/code  →  quickshell -p …/shell.qml
#
#  Everything k4 writes at runtime lives outside the code: settings and
#  plugin state in ~/.local/state/k4, user plugins in ~/.config/k4/plugins.
#  The mirror is only the code, and only k4's own writes (recargas, externos)
#  land in it — which is exactly what the read-only store could not host.
#
#  Updating: `nix flake update`. The next launch notices the store path
#  changed and re-materializes the mirror. The bar's own git updater is not
#  used — there is no .git in the mirror on purpose, and Settings reports
#  «sin-git» instead of offering an update that would fight Nix.
set -eu

src="@out@/share/k4"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
conf="${XDG_CONFIG_HOME:-$HOME/.config}"
mirror="$data/k4/code"

#  Every helper the bar shells out to, per dependencias.tsv. The user's own
#  PATH stays last, so a locally installed tool still wins if they want one.
#  It goes first because the sync below already needs mkdir, cp, mv.
export PATH="@binpath@${PATH:+:$PATH}"

# ─── The writable mirror ─────────────────────────────────────────────────────
#  `.k4-origen` records which store path the mirror was copied from. Same
#  path → nothing to do, which is the common case: one check, one stat.
if [ ! -f "$mirror/.k4-origen" ] || [ "$(cat "$mirror/.k4-origen" 2>/dev/null)" != "$src" ]; then
    mkdir -p "$data/k4" "$conf/k4/plugins"
    tmp="$data/k4/.code.tmp.$$"
    old="$data/k4/.code.old"
    rm -rf "$tmp" "$old"

    #  `cp -a` keeps modes, and store files are read-only: the mirror has to
    #  be writable or `pluginReload` dies mid-flight.
    cp -a "$src" "$tmp"
    chmod -R u+w "$tmp"
    printf '%s\n' "$src" > "$tmp/.k4-origen"

    #  The bridge user plugins come in through. tools/plugins.py maintains it
    #  too — creating it here just means the flow works even before the user
    #  ever runs a tools/ script by hand.
    ln -sfn "$conf/k4/plugins" "$tmp/externos"

    #  Drop Qt's compiled-QML disk cache whenever the mirror changes.
    #
    #  The cache keys compiled code on file path + mtime, and store files
    #  are all stamped epoch (Dec 31 1969), which `cp -a` preserves: after a
    #  re-sync a CHANGED .qml still looks unchanged, so the old compiled
    #  version keeps loading — a new property reads as «non-existent» and a
    #  plugin dies with it. Quickshell rebuilds the cache on the next start;
    #  the cost is one slower first launch after an update.
    qscache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
    rm -rf "$qscache/qmlcache" "$qscache"/qtpipelinecache-*

    if [ -d "$mirror" ]; then
        mv -T "$mirror" "$old"
    fi
    mv -T "$tmp" "$mirror"
    rm -rf "$old"
fi

# ─── The Qt environment ──────────────────────────────────────────────────────
#  quickshell from nixpkgs does not pull qtmultimedia, and k4 needs it (the
#  editor, the video wallpapers). The engine finds the extra QML module and
#  the ffmpeg backend through these paths; `arrancar` then prepends its own
#  `api/` for the K4 module on top of whatever we set here.
export NIXPKGS_QT6_QML_IMPORT_PATH="@qtQml@${NIXPKGS_QT6_QML_IMPORT_PATH:+:$NIXPKGS_QT6_QML_IMPORT_PATH}"
export QML_IMPORT_PATH="@qtQml@${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QT_PLUGIN_PATH="@qtPlugins@${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
#  nixpkgs builds both the ffmpeg and the gstreamer backends; without this
#  the engine may pick gstreamer, whose plugins are not in the environment.
export QT_MEDIA_BACKEND=ffmpeg

#  The fonts k4 is written against: Adwaita Sans for text, MesloLGS Nerd Font
#  Mono for every icon. This file includes the system configuration, so other
#  fonts keep working.
export FONTCONFIG_FILE="@fontconf@"

#  ── and nothing else: the how-to-start-it logic is upstream's, in `arrancar`
#  (QML_IMPORT_PATH for `import K4`, the log in ~/.local/state/k4). Whatever
#  arguments came in — `--no-duplicate -d` from the Hyprland hook, say — go
#  through untouched.
exec "$mirror/arrancar" "$@"
