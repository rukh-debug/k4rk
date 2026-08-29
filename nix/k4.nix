#  k4, packaged for Nix.
#
#  The store path holds the code and the environment; a small launcher
#  (nix/k4-launcher.sh) materializes a writable copy in
#  ~/.local/share/k4/code at first run, because k4 writes into its own
#  checkout (the `externos` bridge, the `recargas/` hot-reload folders) and
#  the store is read-only.
#
#  The dependency list mirrors dependencias.tsv — the project's single
#  source of truth. Everything marked `base` that exists in nixpkgs is
#  here; optional ones (whisper, yay, nvidia-smi, claude, codex) are left
#  to the user, exactly as `./instalar` leaves them unless asked.
{
  lib,
  stdenvNoCC,
  makeFontsConf,

  #  the engine and the compositor it integrates with
  quickshell,
  hyprland,

  #  helpers the bar shells out to
  coreutils,
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
  pulseaudio, #  pactl — the client works against pipewire-pulse too
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

  #  the two fonts k4 is written against
  adwaita-fonts,
  nerd-fonts, #  .meslo-lg → «MesloLGS Nerd Font Mono», every icon in the bar

  #  Qt: quickshell does not pull the multimedia module, and k4's editor and
  #  video wallpapers need it (the ffmpeg backend rides along in its plugins)
  qt6,

  #  k4 itself
  src,
  version ? "unstable",
}:

let
  #  Everything the launcher needs, as one substitution each. `out` resolves
  #  at install time; the rest are input paths, known now.
  qtQml = "${qt6.qtmultimedia}/lib/qt-6/qml";
  qtPlugins = "${qt6.qtmultimedia}/lib/qt-6/plugins";
  #  A fontconfig that keeps the system fonts (the include) and adds the two
  #  k4 needs. The launcher exports FONTCONFIG_FILE pointing at it.
  fontsConf = makeFontsConf {
    fontDirectories = [
      "${adwaita-fonts}/share/fonts"
      "${nerd-fonts.meslo-lg}/share/fonts"
    ];
    includes = [ "/etc/fonts/fonts.conf" ];
  };
  binpath = lib.makeBinPath [
    coreutils #  the launcher and `arrancar` themselves: cp, mkdir, mv, tee…
    quickshell
    hyprland
    python3
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
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "k4";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true; #  plain files + a shell launcher; no ELF of ours to patch

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/k4" "$out/bin" "$out/etc/fonts"
    cp -a . "$out/share/k4/"
    #  Nothing in the mirror needs the git history, and its presence would
    #  make Settings offer an update path that fights the flake.
    rm -rf "$out/share/k4/.git"

    #  The launcher. `--subst-var out` is why this is not substituteAll:
    #  the script must name the store path it lives in.
    substitute ${./k4-launcher.sh} "$out/bin/k4" \
      --subst-var out \
      --subst-var-by qtQml "${qtQml}" \
      --subst-var-by qtPlugins "${qtPlugins}" \
      --subst-var-by binpath "${binpath}" \
      --subst-var-by fontconf "$out/etc/fonts/k4-fonts.conf"
    chmod 555 "$out/bin/k4"

    install -Dm444 "${fontsConf}" "$out/etc/fonts/k4-fonts.conf"

    runHook postInstall
  '';

  passthru = {
    #  Where the launcher materializes the writable copy. Home Manager uses
    #  it to point Hyprland's IPC shortcuts at the running instance's path.
    mirrorPath = ".local/share/k4/code";
    inherit quickshell;
  };

  meta = {
    description = "A Dynamic Island for Hyprland, built with Quickshell";
    longDescription = ''
      k4 sits collapsed at the edge of the screen and expands only when it
      has something to say. Everything it does — the clock included — is a
      plugin. This package runs it from a writable mirror of the store path
      so user plugins and hot reload keep working under Nix.
    '';
    homepage = "https://github.com/rukh-debug/k4rk";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "k4";
  };
})
