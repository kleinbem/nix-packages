# Buzz Desktop — Tauri client for Buzz (github.com/block/buzz), the
# Nostr-based team chat/git/agent-workspace relay this fleet self-hosts
# (nix-presets/containers/buzz.nix). Staged derivation matching upstream PR
# https://github.com/NixOS/nixpkgs/pull/569165.
{
  lib,
  appimageTools,
  fetchurl,
  gst_all_1,
  xdg-utils,
}:
let
  pname = "buzz-desktop";
  version = "0.5.26";

  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v${version}/Buzz_${version}_amd64.AppImage";
    hash = "sha256-67HFouhjceRMawqqdO9X6AwphliNnxftpSTcQ4iTz0M=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };

  gstPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
  ];
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs =
    pkgs:
    with pkgs;
    [
      elfutils
      gtk3
      webkitgtk_4_1
      libayatana-appindicator
      zstd
      xdg-utils
    ]
    ++ gstPlugins;

  extraBwrapArgs = [
    "--setenv"
    "GST_PLUGIN_PATH_1_0"
    (lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins)
    "--setenv"
    "GST_REGISTRY_1_0"
    "/tmp/buzz-desktop-gst-registry.bin"
    "--setenv"
    "BROWSER"
    "${xdg-utils}/bin/xdg-open"
  ];

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/buzz-desktop.png $out/share/icons/hicolor/512x512/apps/${pname}.png
    install -Dm444 ${appimageContents}/Buzz.desktop $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=buzz-desktop' 'Exec=${pname}' \
      --replace-fail 'Icon=buzz-desktop' "Icon=${pname}"
  '';

  meta = {
    description = "Desktop client for Buzz, a Nostr-based workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = pname;
    maintainers = with lib.maintainers; [ kleinbem ];
    platforms = [ "x86_64-linux" ];
  };
}
