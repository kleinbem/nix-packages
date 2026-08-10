# Buzz Desktop — Tauri client for Buzz (github.com/block/buzz), the
# Nostr-based team chat/git/agent-workspace relay this fleet self-hosts
# (nix-presets/containers/buzz.nix). Vendored as a prebuilt-binary release,
# same pattern as google-antigravity-cli/oh-my-pi in this repo — no upstream
# nixpkgs package or flake exists yet (app is ~2 weeks old at packaging time).
#
# Packaged from the upstream AppImage via appimageTools.wrapType2 rather than
# building the Tauri app from source: the desktop app is a full Rust+Vite
# frontend build (separate from buzz-relay's plain-Rust build, which nix-presets
# already does from source) — a reproducible npm dependency lock plus wiring
# the Tauri bundler is real, separate work, not something to bundle into a
# quick client-access fix. Revisit a from-source build if the AppImage route
# ever becomes a maintenance burden (e.g. upstream stops shipping one).
#
# Bump: grab the new tag's AppImage asset URL from
# https://github.com/block/buzz/releases (tag pattern `desktop-vX.Y.Z`) and
# re-hash with `nix-prefetch-url --type sha256 <url>`.
{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "buzz-desktop";
  version = "0.5.8";

  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v${version}/Buzz_${version}_amd64.AppImage";
    hash = "sha256-VVWoJA8cyipv9BtCwme+GjcP/kKN1Lt+1wL3AU4SHYs=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # appimageTools' default FHS package set is generic multimedia/X11 —
  # useful, but neither GTK+WebKit (Tauri's actual rendering engine) nor
  # elfutils are in it. Confirmed live 2026-08-10 by running the wrapped
  # binary directly: it failed on the first missing lib each time
  # (libelf.so.1, then webkit2gtk), so these are the real, not guessed,
  # gaps — not a defensive "add everything" list.
  extraPkgs = pkgs: [
    pkgs.elfutils # libelf.so.1
    pkgs.gtk3
    pkgs.webkitgtk_4_1
    pkgs.libayatana-appindicator # tray icon support
    pkgs.zstd # libzstd.so.1
  ];

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/buzz-desktop.png $out/share/icons/hicolor/512x512/apps/${pname}.png
    install -Dm444 ${appimageContents}/Buzz.desktop $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=buzz-desktop' 'Exec=${pname}' \
      --replace-fail 'Icon=buzz-desktop' "Icon=${pname}"
  '';

  meta = {
    description = "Desktop client for Buzz — Nostr-based team chat/git/agent workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
