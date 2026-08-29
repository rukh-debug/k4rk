#  The hacking shell: `nix develop`.
#
#  Everything the bar's own tooling expects — the validators the README asks
#  for before a PR, the `--test` plugin runner, the editor tests that need
#  real ffmpeg — against a checkout, not the store copy.
{
  lib,
  mkShell,
  makeFontsConf,
  quickshell,
  hyprland,
  python3,
  git,
  curl,
  grim,
  slurp,
  satty,
  wf-recorder,
  swaybg,
  ffmpeg,
  imagemagick,
  zenity,
  wl-clipboard,
  fd,
  pulseaudio,
  wireplumber,
  networkmanager,
  bluez,
  libnotify,
  xdg-utils,
  xdg-user-dirs,
  desktop-file-utils,
  openssh,
  procps,
  util-linux,
  getent,
  adwaita-fonts,
  nerd-fonts,
  qt6,
}:

mkShell {
  packages =
    [
      quickshell
      hyprland
      #  tools/ beyond the standard library: spritesheet wants PIL and numpy,
      #  glifos wants fontTools (and skips itself without it)
      (python3.withPackages (ps: with ps; [
        numpy
        pillow
        fonttools
      ]))
      git
      curl
      grim
      slurp
      satty
      wf-recorder
      swaybg
      ffmpeg
      imagemagick
      zenity
      wl-clipboard
      fd
      pulseaudio
      wireplumber
      networkmanager
      bluez
      libnotify
      xdg-utils
      xdg-user-dirs
      desktop-file-utils
      openssh
      procps
      util-linux
      getent
    ]
    ++ [
      #  fonts for qmllint-adjacent runs and the glyph tools
      adwaita-fonts
      nerd-fonts.meslo-lg
    ];

  #  Same Qt environment the packaged launcher sets: the K4 QML module is
  #  the checkout's own api/, and QtMultimedia comes from nixpkgs.
  NIXPKGS_QT6_QML_IMPORT_PATH = "${qt6.qtmultimedia}/lib/qt-6/qml";
  QML_IMPORT_PATH = "${qt6.qtmultimedia}/lib/qt-6/qml";
  QT_PLUGIN_PATH = "${qt6.qtmultimedia}/lib/qt-6/plugins";
  QT_MEDIA_BACKEND = "ffmpeg";

  #  The fonts k4 is written against, for `./arrancar` and the glyph tools.
  FONTCONFIG_FILE = toString (makeFontsConf {
    fontDirectories = [
      "${adwaita-fonts}/share/fonts"
      "${nerd-fonts.meslo-lg}/share/fonts"
    ];
    includes = [ "/etc/fonts/fonts.conf" ];
  });

  shellHook = ''
    #  The K4 module resolves against THIS checkout, so it goes first and
    #  the QtMultimedia path stays behind it.
    export QML_IMPORT_PATH="$PWD/api''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
    export NIXPKGS_QT6_QML_IMPORT_PATH="$PWD/api''${NIXPKGS_QT6_QML_IMPORT_PATH:+:$NIXPKGS_QT6_QML_IMPORT_PATH}"

    echo "k4 dev shell — quickshell $(quickshell --version 2>/dev/null | head -1)"
    echo "  nix develop   · this shell, against the checkout"
    echo "  ./arrancar    · run the bar from here"
    echo "  python3 tools/plugins.py --test <id>   · a plugin alone"
  '';
}
