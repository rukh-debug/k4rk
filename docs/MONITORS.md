# Monitor settings

Settings → Display → Monitor configures Lua Hyprland outputs. The initial backend
targets Hyprland 0.56.2. Open it with `k4 settingsSection monitor` through the
existing Quickshell IPC target. Other compositors are not supported by this page.

## Controls

- Connected outputs, including disabled outputs; Identify labels active screens.
- Logical arrangement canvas, edge snapping, row arrangement, arrow-key movement
  (Shift for ten logical pixels), and exact X/Y coordinates.
- Advertised resolutions and refresh rates, mode-valid scale presets and a custom
  percentage, all eight transforms, output enablement, and native mirroring.
- Draft editing: Apply previews the whole layout; Discard restores the live view.
- A 15-second Keep/Revert prompt appears independently of Settings on each screen.
  Closing Settings does not cancel the recovery worker.

At least one independent output must remain enabled. Mirror sources must be
enabled independent outputs. Scale validation requires whole logical pixels.
Unsupported mode combinations are rejected before mutation. External changes
invalidate an edited draft; Discard adopts the current configuration.

## Persistent ownership

Enable the Home Manager option:

```nix
programs.k4.monitors.enable = true;
```

This requires Home Manager-managed Lua Hyprland. It appends a monitor-only hook at order 1500,
after ordinary declarative output defaults. Put any other output defaults before
that hook. It is independent of `programs.k4.hyprland.hookIntoConfig`.

The hook runs the packaged generator and loads its Lua output from
`outputs` in `$XDG_STATE_HOME/k4/monitors/profile.json`. Hardware-specific profiles
are local data and are not part of the shareable configuration. Only explicit
Keep writes that section, atomically. It is loaded at compositor start/reload
before the bar needs to be running. A runtime capability marker tells the preview
helper that this integration is installed. Configurations without this option offer
session-only Keep. Activate Home Manager and reload Hyprland after enabling it.

The generated rules own mode, position, scale, transform, disabled state and mirror
source. They do not modify advanced color/VRR/workspace policies. Saved disable and
mirror rules are conditional on a saved source being present; if enumeration is
empty during startup they fail open, preserving fallback outputs. Connector names
are used in this first version; port-independent profile matching is future work.

To return to declarative defaults, remove `outputs` from the local monitor profile, then reload
Hyprland. This is currently a manual operation; the page does not provide a reset
button. Disabling the module option stops loading overrides on subsequent reloads.

## Transaction protocol

`tools/monitors.py` exposes JSON CLI requests:

- `inspect`: current outputs, baseline fingerprint, persistence mode, transaction.
- `begin`: one JSON line on stdin with `outputs` and `fingerprint`.
- `keep TOKEN` / `revert TOKEN`: acknowledge the current preview.

A detached Python process inherits an exclusive session lock before applying any
changes. It owns a private Unix socket, the monotonic deadline, and rollback. It
survives exit of the requesting process and Quickshell. Socket requests include a
transaction token; the worker serializes confirmation and timeout. This is a
detached worker, not a systemd-supervised daemon. Killing that worker with SIGKILL
prevents its recovery code from running; a pending preview is never written into
the persistent include before confirmation.

Runtime files live under `$XDG_RUNTIME_DIR/k4-monitors-<session-hash>/`. An old
session's IPC stays scoped to that compositor signature. Apply uses argv-based
`hyprctl eval` and properly escaped Lua strings. A successful command alone is
insufficient: mode, scale, transform, enabled state, position and mirror source are
read back before the prompt. Readback polling catches external layout changes and
hotplug during confirmation. A reload that produces exactly the same output state
is indistinguishable from no change in this initial polling implementation.

Rollback restores the connected portion of the snapshot. If that leaves no
independent screen, a connected output is enabled at preferred mode and scale 1.
Recovery failure remains visible in the page; it is not reported as success.

## Verification

`python3 -B tools/test_monitors.py` runs normalization/validation tests and detached
worker integration tests using a fake `hyprctl`. Tests use isolated runtime, config
and state directories and never change the real desktop. The suite is also the
flake's `monitors` check.

On hardware, check fractional refresh, scaling, portrait rotation, mirror-to-extend,
disabled-output discovery, hot-unplug, Settings closing during a preview, timeout,
and Keep followed by compositor reload. Test the page at reduced logical sizes.

## Follow-up phases

1. A transaction-backed Restore Nix defaults action and a sticky page action strip.
2. Named/versioned profiles, stable monitor identities, profile import/export.
3. Opt-in docking automation, conflict handling and previously-confirmed matching.
4. Capability discovery followed by VRR, bit depth, HDR/ICC, physical brightness,
   and workspace associations. Current-state fields are not capability flags.

Research references: [DMS display configuration](https://github.com/AvengeMedia/DankMaterialShell/tree/c2c36d7e21b0afa56745e18d9c6ad0cf5c5ac59b/quickshell/Modules/Settings/DisplayConfig),
[Noctalia legacy Monitor Layout](https://github.com/noctalia-dev/legacy-v4-plugins/tree/main/monitor-layout),
[Noctalia Lua mirroring](https://github.com/noctalia-dev/community-plugins/tree/main/hypr-screen-mirror),
[Hyprland's installed Lua rule implementation](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/config/lua/bindings/LuaBindingsConfigRules.cpp).
