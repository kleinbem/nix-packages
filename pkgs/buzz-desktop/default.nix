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
  gst_all_1,
  firefox-beta,
  writeShellScript,
}:
let
  pname = "buzz-desktop";
  version = "0.5.8";

  src = fetchurl {
    url = "https://github.com/block/buzz/releases/download/desktop-v${version}/Buzz_${version}_amd64.AppImage";
    hash = "sha256-VVWoJA8cyipv9BtCwme+GjcP/kKN1Lt+1wL3AU4SHYs=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };

  # GStreamer element lookups (appsink/appsrc/autoaudiosink) fail inside
  # this FHS wrapper regardless of which plugin packages are included.
  # Confirmed live 2026-08-10 this is FATAL, not cosmetic: the failed
  # lookup trips a GLib critical assertion inside WebKitWebProcess
  # (`g_object_set: assertion 'G_IS_OBJECT (object)' failed` etc.), which
  # this WebKitGTK build treats as fatal — WebKitWebProcess SIGABRTs
  # every single launch (journalctl: "ANOM_ABEND ... comm=WebKitWebProces
  # sig=6"), which is why the window shows nothing: the process that
  # would render the page is dead before it gets the chance.
  #
  # Root cause (found by tracing the actual exec chain: bwrap -> container-init
  # -> /etc/profile -> appimage-exec.sh -> AppRun -> AppRun.wrapped -> the
  # buzz-desktop shim -> buzz-desktop.bin): AppRun.wrapped (linuxdeploy's
  # compiled launcher, confirmed via `strings` on the extracted AppImage) force
  # -overwrites GST_PLUGIN_SYSTEM_PATH_1_0 to point at the AppImage's own bundle
  # dir. Upstream's own workaround for this (usr/bin/buzz-desktop, a shim
  # installed by their desktop/scripts/fix-appimage.sh) unsets any GST_PLUGIN_*
  # var whose value contains the AppDir path as a *substring* — but since
  # AppRun.wrapped prepends its bad path in front of whatever we set (rather
  # than replacing outright), the combined string still contains the AppDir
  # substring, so the shim throws away our real plugin paths along with the
  # bad prefix. GST_PLUGIN_PATH_1_0 (additive search path, as opposed to
  # GST_PLUGIN_SYSTEM_PATH_1_0 which replaces the default search) is never
  # touched by AppRun.wrapped at all (absent from its `strings` output) and
  # therefore never matches the shim's substring check either — it survives
  # untouched all the way to the real binary. Confirmed live 2026-08-10.
  gstPlugins = [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad # AAC decoding (faad) — confirmed missing live 2026-08-10
  ];

  # See the long comment on extraBwrapArgs' BROWSER entry below: pointing
  # BROWSER straight at the firefox binary (first attempt) launches it with
  # no profile, which collides with the "standard" profile already locked
  # by this fleet's normal always-running firefox-beta instance — a
  # DIFFERENT nixpkgs-pinned version at that, since this derivation's own
  # firefox-beta isn't the same build the user's interactive session is
  # running. This wrapper restores the "-P standard" targeting so the URL
  # correctly hands off to the already-running instance instead of a second
  # instance silently failing to grab a locked profile. Confirmed live
  # 2026-08-10: bare binary produced no error and no window; needs testing
  # whether this wrapper resolves it.
  browserWrapper = writeShellScript "buzz-desktop-browser" ''
    exec ${firefox-beta}/bin/firefox -P standard "$@"
  '';
in
appimageTools.wrapType2 {
  inherit pname version src;

  # appimageTools' default FHS package set is generic multimedia/X11 —
  # useful, but neither GTK+WebKit (Tauri's actual rendering engine) nor
  # elfutils are in it. Confirmed live 2026-08-10 by running the wrapped
  # binary directly: it failed on the first missing lib each time
  # (libelf.so.1, then webkit2gtk), so these are the real, not guessed,
  # gaps — not a defensive "add everything" list.
  extraPkgs =
    pkgs:
    [
      pkgs.elfutils # libelf.so.1
      pkgs.gtk3
      pkgs.webkitgtk_4_1
      pkgs.libayatana-appindicator # tray icon support
      pkgs.zstd # libzstd.so.1
    ]
    ++ gstPlugins;

  # NOT wrapProgram --set (tried first, wrong): that sets the var on the
  # OUTER wrapper script's shell, but that script's final step execs
  # `bwrap`, which does NOT forward arbitrary parent env vars into the
  # sandbox namespace it constructs — confirmed live 2026-08-10 by
  # reading /proc/<sandboxed-child>/environ directly: zero GST_* vars
  # present despite wrapProgram setting one. bwrap needs the variable
  # explicitly re-declared via --setenv on ITS OWN command line, which is
  # exactly what extraBwrapArgs threads through to (a buildFHSEnv option,
  # passed through by appimageTools.wrapType2's extendMkDerivation).
  #
  # NOT GST_PLUGIN_SYSTEM_PATH_1_0 (tried first, also wrong, for a
  # different reason than wrapProgram): see the long comment on gstPlugins
  # above — that variable name gets force-clobbered by AppRun.wrapped and
  # then stripped again by upstream's own AppImage shim. GST_PLUGIN_PATH_1_0
  # is untouched by both and reaches the real binary intact.
  #
  # GST_REGISTRY_1_0 too, not just the plugin path: upstream's own tracker
  # (block/buzz#2560, still open) documents that the AppImage's default
  # GStreamer registry cache is the SHARED desktop-wide one
  # (~/.cache/gstreamer-1.0/registry.x86_64.bin) — the same file any other
  # GStreamer app on the host reads/writes. A scan done under one
  # environment (e.g. before this package's GST_PLUGIN_PATH_1_0 fix
  # existed, or by an entirely different app) can leave stale/empty
  # results that a later run reuses instead of rescanning, which is
  # consistent with why clearing ~/.cache/gstreamer-1.0 by hand didn't
  # reliably fix this. Upstream's own suggested fix #1 for that issue is
  # exactly this: give the app a private registry instead of sharing the
  # desktop-wide one.
  extraBwrapArgs = [
    "--setenv"
    "GST_PLUGIN_PATH_1_0"
    (lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins)
    "--setenv"
    "GST_REGISTRY_1_0"
    "/tmp/buzz-desktop-gst-registry.bin"
    # This fleet's global $BROWSER (users/martin/home.nix) is
    # "<firefox-beta> -P standard" — a binary+flag string, following the
    # traditional Unix $BROWSER convention of being shell-invoked. buzz-
    # desktop's Rust "webbrowser" crate instead does a bare
    # Command::new(env::var("BROWSER")) with no shell splitting, so it
    # tries to execve the literal string including the " -P standard"
    # suffix as one filename and fails silently ("No such file or
    # directory", confirmed live 2026-08-10 by reproducing the exact
    # Command::new() call by hand) — the sign-in browser window never
    # opens.
    #
    # First fix attempt (bare firefox binary path, no -P flag) resolved
    # that crash but produced a second, silent failure: this derivation's
    # firefox-beta is a different nixpkgs-pinned build than whatever
    # version is already running interactively on the host, and Firefox
    # refuses to open the locked "standard" profile from a second,
    # different-version instance — no error, just no window. browserWrapper
    # (defined above) restores "-P standard" so it hands off to the
    # existing running instance correctly, while still being a single
    # executable path so Command::new() doesn't choke on embedded args.
    # Scoped to this sandbox only; the fleet-wide $BROWSER convention for
    # every other app is untouched.
    "--setenv"
    "BROWSER"
    "${browserWrapper}"
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
