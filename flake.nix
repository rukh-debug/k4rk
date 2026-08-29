{
  description = "k4 — a Dynamic Island for Hyprland, built with Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      #  One version string for every output: the commit when built from a
      #  flake checkout, a date otherwise.
      version = self.shortRev or self.dirtyShortRev or "unstable-${self.lastModifiedDate or "19700101"}";

      mkK4 =
        pkgs:
        pkgs.callPackage ./nix/k4.nix {
          src = self;
          inherit version;
        };
    in
    {
      packages = forAllSystems (pkgs: rec {
        k4 = mkK4 pkgs;
        default = k4;
      });

      apps = forAllSystems (pkgs: {
        k4 = {
          type = "app";
          program = "${mkK4 pkgs}/bin/k4";
        };
        default = self.apps.${pkgs.system}.k4;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/devshell.nix { };
      });

      overlays.default = final: _prev: {
        k4 = final.callPackage ./nix/k4.nix { src = ./.; };
      };

      homeManagerModules.k4 = ./nix/home-manager.nix;
      nixosModules.k4 = ./nix/nixos.nix;

      checks = forAllSystems (pkgs: {
        k4 = mkK4 pkgs;

        #  The Home Manager module must evaluate with the integration on,
        #  both config flavors, and off.
        home-manager-hyprlang =
          (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              (
                { config, ... }:
                {
                  home.username = "test";
                  home.homeDirectory = "/home/test";
                  home.stateVersion = "25.11";
                  wayland.windowManager.hyprland = {
                    enable = true;
                    configType = "hyprlang";
                  };
                  programs.k4.enable = true;
                }
              )
              self.homeManagerModules.k4
            ];
          }).activation-script;

        home-manager-lua =
          (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              (
                { config, ... }:
                {
                  home.username = "test";
                  home.homeDirectory = "/home/test";
                  home.stateVersion = "26.05";
                  wayland.windowManager.hyprland = {
                    enable = true;
                    configType = "lua";
                  };
                  programs.k4.enable = true;
                }
              )
              self.homeManagerModules.k4
            ];
          }).activation-script;

        home-manager-no-hypr =
          (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              (
                { config, ... }:
                {
                  home.username = "test";
                  home.homeDirectory = "/home/test";
                  home.stateVersion = "25.11";
                  programs.k4.enable = true;
                }
              )
              self.homeManagerModules.k4
            ];
          }).activation-script;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
