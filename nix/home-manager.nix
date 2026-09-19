#  Home Manager module: programs.k4.
#
#  What it does:
#    · puts the k4 package on PATH (`k4` runs the bar, syncing the
#      ~/.local/share/k4/code mirror first);
#    · writes the Hyprland integration from the repo's own templates —
#      hypr/k4.conf and hypr/config/k4.lua — with three substitutions:
#        - the exec hook launches the wrapper, not $mirror/launch,
#          because on a cold start the mirror does not exist yet and the
#          wrapper is what creates it;
#        - IPC shortcuts target $mirror/shell.qml, the path the running
#          instance was started under (`quickshell ipc -p` must match it);
#        - `quickshell` becomes an absolute path, so nothing depends on
#          the session's PATH.
#
#  Hooking the file into hyprland.conf only happens when Home Manager's
#  own Hyprland module is enabled — editing a hand-managed configuration
#  is the installer's job, not a declarative module's. Without the module,
#  add the source line yourself:
#
#      source = ~/.config/hypr/k4.conf
#
#  (or `require("config.k4")` in hyprland.lua — both files are written.)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.k4;

  #  XDG_DATA_HOME as an absolute path, the way the launcher computes it.
  dataHome =
    let
      d = config.xdg.dataHome;
    in
    if lib.hasPrefix "$HOME" d then
      "${config.home.homeDirectory}${lib.removePrefix "$HOME" d}"
    else
      d;

  #  XDG_CONFIG_HOME, absolutized the same way — hyprland.conf does not
  # expand $HOME in `source` paths.
  configHome =
    let
      d = config.xdg.configHome;
    in
    if lib.hasPrefix "$HOME" d then
      "${config.home.homeDirectory}${lib.removePrefix "$HOME" d}"
    else
      d;

  mirror = "${dataHome}/k4/code";

  stateHome = lib.replaceStrings [ "$HOME" ] [ config.home.homeDirectory ] config.xdg.stateHome;
  monitorInclude = ''
    -- Confirmed k4 monitor overrides load after the declarative defaults.
    do
      local path = ${builtins.toJSON "${stateHome}/k4/monitors/confirmed.lua"}
      local file = io.open(path, "r")
      if file then
        file:close()
        local ok, message = pcall(dofile, path)
        if not ok then print("k4 monitor override: " .. tostring(message)) end
      end
    end
  '';

  hypr = config.wayland.windowManager.hyprland;

  #  Home Manager 26.05 can generate Lua Hyprland configs; older versions
  #  only speak hyprlang. The hook differs accordingly.
  hyprIsLua = (hypr.configType or "hyprlang") == "lua";

  #  The quickshell the wrapper puts first in PATH — same nixpkgs, same
  #  binary the bar itself runs under.
  quickshell = cfg.package.quickshell;

  #  The template in play: yours when set, the package's otherwise.
  fuente =
    if cfg.hyprland.template != null then cfg.hyprland.template
    else "${cfg.package}/share/k4/hypr/k4.lua";
  fuenteConf =
    if cfg.hyprland.template != null then cfg.hyprland.template
    else "${cfg.package}/share/k4/hypr/k4.conf";

  #  hypr/k4.conf (or k4.lua) with @RAIZ@ resolved. Order matters: the
  #  exec-once line embeds @RAIZ@ itself, so it goes before the blanket
  #  substitution. The bar starts through the package's `bin/k4` — the
  #  launcher owns the mirror, the environment and the log — whichever
  #  spelling the template uses for the start script (`launch`, and the
  #  old `arrancar` for templates written before the rename).
  substituteTemplate =
    path:
    builtins.replaceStrings
      [
        "exec-once = @RAIZ@/launch"
        "raiz .. \"/launch"
        "exec-once = @RAIZ@/arrancar"
        "raiz .. \"/arrancar"
        "@RAIZ@"
        "quickshell ipc"
      ]
      [
        "exec-once = ${cfg.package}/bin/k4"
        "\"${cfg.package}/bin/k4"
        "exec-once = ${cfg.package}/bin/k4"
        "\"${cfg.package}/bin/k4"
        mirror
        "${quickshell}/bin/quickshell ipc"
      ]
      (builtins.readFile path);
in
{
  options.programs.k4 = {
    enable = lib.mkEnableOption "k4, a Dynamic Island for Hyprland";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./k4.nix { src = ../.; };
      defaultText = lib.literalExpression "pkgs.k4";
      description = "The k4 package to use.";
    };

    monitors.enable = lib.mkEnableOption "persistent, confirmed k4 monitor overrides (Lua Hyprland only)";
    nightLight.enable = lib.mkEnableOption "the Hyprland-session night-light backend controlled by k4";

    hyprland = {
      writeConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Write the Hyprland integration from the package's templates.
          Only the file matching the configuration flavor is written when
          Home Manager manages Hyprland (k4.lua for `configType = "lua"`,
          k4.conf otherwise); both are written when it does not, since
          there is no way to know which one a hand-written configuration
          will source.
        '';
      };

      hookIntoConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Add the `source` line for k4.conf when
          wayland.windowManager.hyprland is managed by Home Manager.
          Has no effect on hand-written configurations.
        '';
      };

      template = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Your own Hyprland template instead of the package's
          (share/k4/hypr/k4.lua for the Lua flavor, k4.conf otherwise).
          Rendered as the flavor-appropriate file, with the same
          substitutions applied: @RAIZ@ → the writable mirror,
          `quickshell ipc` → the absolute binary, and the exec-once hook
          rewritten to the wrapper.

          The point of the option: keybinds are machine taste, and the
          Hyprland Lua API accumulates binds instead of replacing them,
          so a colliding key must be removed from the template — editing
          upstream's template for that puts your layout in a public repo.
          Keep a fork's template upstream-pure and carry the layout here.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !cfg.monitors.enable || (hypr.enable && hyprIsLua);
      message = "programs.k4.monitors.enable requires Home Manager-managed Lua Hyprland.";
    }];
    home.packages = [ cfg.package ];

    # One backend instance, independent of bar reloads. k4 owns the schedule;
    # hyprsunset starts neutral and only applies the requested transformation.
    services.hyprsunset = lib.mkIf cfg.nightLight.enable {
      enable = true;
      package = cfg.package.hyprsunset;
      systemdTarget = "hyprland-session.target";
      extraArgs = [ "--identity" ];
      settings.max-gamma = 100;
    };
    systemd.user.services.hyprsunset.Unit.PartOf = lib.mkIf cfg.nightLight.enable
      (lib.mkForce [ "hyprland-session.target" ]);

    #  Only the matching flavor gets a file when Home Manager manages
    #  Hyprland; a stray k4.conf next to a Lua configuration is confusion
    #  waiting for someone to source it.
    xdg.configFile = (lib.optionalAttrs cfg.monitors.enable {
      "k4/monitors.json".text = builtins.toJSON { managed = true; };
    }) // (lib.optionalAttrs cfg.hyprland.writeConfig (
      if hypr.enable && hyprIsLua then
        {
          "hypr/config/k4.lua".text = substituteTemplate fuente;
        }
      else if hypr.enable then
        {
          "hypr/k4.conf".text = substituteTemplate fuenteConf;
        }
      else
        {
          "hypr/k4.conf".text = substituteTemplate fuenteConf;
          "hypr/config/k4.lua".text = substituteTemplate fuente;
        }
    ));

    wayland.windowManager.hyprland.extraConfig = lib.mkMerge [
      (lib.mkIf (cfg.hyprland.writeConfig && cfg.hyprland.hookIntoConfig && hypr.enable)
        (if hyprIsLua then ''require("config.k4")'' else "source = ${configHome}/hypr/k4.conf"))
      (lib.mkIf cfg.monitors.enable (lib.mkOrder 1500 monitorInclude))
    ];
  };
}
