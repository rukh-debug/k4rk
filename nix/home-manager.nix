#  Home Manager module: programs.k4.
#
#  What it does:
#    · puts the k4 package on PATH (`k4` runs the bar, syncing the
#      ~/.local/share/k4/code mirror first);
#    · writes the Hyprland integration from the repo's own templates —
#      hypr/k4.conf and hypr/config/k4.lua — with three substitutions:
#        - the exec hook launches the wrapper, not $mirror/arrancar,
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

  hypr = config.wayland.windowManager.hyprland;

  #  Home Manager 26.05 can generate Lua Hyprland configs; older versions
  #  only speak hyprlang. The hook differs accordingly.
  hyprIsLua = (hypr.configType or "hyprlang") == "lua";

  #  The quickshell the wrapper puts first in PATH — same nixpkgs, same
  #  binary the bar itself runs under.
  quickshell = cfg.package.quickshell;

  #  hypr/k4.conf (or k4.lua) with @RAIZ@ resolved. Order matters: the
  #  exec-once line embeds @RAIZ@ itself, so it goes before the blanket
  #  substitution.
  substituteTemplate =
    path:
    builtins.replaceStrings
      [
        "exec-once = @RAIZ@/arrancar"
        "raiz .. \"/arrancar"
        "@RAIZ@"
        "quickshell ipc"
      ]
      [
        "exec-once = ${cfg.package}/bin/k4"
        "\"${cfg.package}/bin/k4"
        mirror
        "${quickshell}/bin/quickshell ipc"
      ]
      (builtins.readFile "${cfg.package}/share/k4/${path}");
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

    hyprland = {
      writeConfig = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Write the Hyprland integration files (k4.conf and k4.lua) from
          the package's templates. When Home Manager's Hyprland module is
          active, the classic file is also sourced automatically.
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
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile = lib.mkIf cfg.hyprland.writeConfig {
      "hypr/k4.conf".text = substituteTemplate "hypr/k4.conf";
      "hypr/config/k4.lua".text = substituteTemplate "hypr/k4.lua";
    };

    wayland.windowManager.hyprland =
      lib.mkIf (cfg.hyprland.writeConfig && cfg.hyprland.hookIntoConfig && hypr.enable)
        {
          #  Sourced last, matching what ./instalar does: k4's binds are
          #  declared after yours, and the template documents that whoever
          #  rebinds later wins. Raw lines in hyprland.conf, raw Lua in
          #  hyprland.lua — `extraConfig` is verbatim either way.
          extraConfig =
            if hyprIsLua then
              ''require("config.k4")''
            else
              "source = ${configHome}/hypr/k4.conf";
        };
  };
}
