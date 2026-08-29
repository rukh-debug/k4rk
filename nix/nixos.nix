#  NixOS module: programs.k4.
#
#  System-wide install: the package on PATH and the two fonts in the
#  system font set. The bar's own launcher carries its full runtime
#  environment, so this is convenience, not a requirement — `nix run`
#  works without any of it.
#
#  Autostart is left to the compositor config (see the Home Manager
#  module for the Hyprland wiring); a NixOS module has no business
#  guessing where your session comes from.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.k4;
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
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    #  For everything else on the system that renders text: the bar brings
    #  its own fontconfig, but a terminal asking for “Adwaita Sans” should
    #  not get squares back either.
    fonts.packages = with pkgs; [
      adwaita-fonts
      nerd-fonts.meslo-lg
    ];
  };
}
