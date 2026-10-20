{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchPnpmDeps,
  runCommand,
  cargo-tauri,
  cmake,
  perl,
  pkg-config,
  jq,
  nodejs_24,
  pnpm_10,
  pnpmConfigHook,
  wrapGAppsHook3,
  makeBinaryWrapper,
  alsa-lib,
  gtk3,
  libsoup_3,
  webkitgtk_4_1,
  glib-networking,
  openssl,
  gst_all_1,
  onnxruntime,
  sherpa-onnx,
  goose-cli,
  cacert,
  nix-update-script,
}:

let
  # Upstream pins pnpm 10 (`packageManager` in package.json) and builds with Node.js 24
  # (node-version in .github/workflows/release.yml).
  pnpm = pnpm_10.override {
    nodejs-slim = nodejs_24;
  };

  rustTarget = stdenv.hostPlatform.rust.rustcTarget;

  # WebKit plays Berd's sounds and voice audio through GStreamer and aborts without an audio
  # sink (the AppImage variant of this is block/berd#195).
  gstreamerPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
  ];
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "berd";
  version = "0.6.4";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "block";
    repo = "berd";
    tag = "v${finalAttrs.version}";
    hash = "sha256-fTk5T1RyPyRpJlQsqjv81Kn+KZlVKHwuwg1k+9S8Doo=";
  };

  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";
  cargoHash = "sha256-c9crSnefbGYl5H6KTn83hHTQXsSGxe5O5El4zTVxgXM=";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-zjz2t9LriG3HhfMuKsvkdee+0su4UTC3+EnboeHq35o=";
  };

  postPatch = ''
    # Link against sherpa-onnx from nixpkgs instead of downloading prebuilt static libraries
    # in the build script. Every dependent must opt out of the default `static` feature, or
    # Cargo unifies both.
    substituteInPlace src-tauri/Cargo.toml \
      --replace-fail 'berd-voice = { path = "crates/berd-voice", features = ["static"] }' \
        'berd-voice = { path = "crates/berd-voice", default-features = false, features = ["shared"] }'
    substituteInPlace src-tauri/crates/berd-voice/Cargo.toml \
      --replace-fail 'default = ["static"]' 'default = []'

    # Tauri checks that every `externalBin` exists, with the target triple appended, at build
    # time. Upstream's release builds Goose from the commit in goose-backend.lock.json; this
    # package uses nixpkgs' goose-cli instead (Berd only needs `goose serve`, see GOOSE_BIN in
    # upstream's README), so Goose stays maintained in one place.
    mkdir -p src-tauri/binaries
    ln -s ${lib.getExe goose-cli} src-tauri/binaries/goosed-${rustTarget}
    # Catch (block/catch) is macOS-only; upstream's script stages its own stub on other platforms.
    bash scripts/prepare-catch-sidecar.sh ${rustTarget}
  '';

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
    jq
    cargo-tauri.hook
    nodejs_24
    pnpm
    pnpmConfigHook
    wrapGAppsHook3
    makeBinaryWrapper
  ];

  buildInputs = [
    alsa-lib
    gtk3
    libsoup_3
    webkitgtk_4_1
    glib-networking
    openssl
    # shared sherpa-onnx links against onnxruntime
    onnxruntime
    sherpa-onnx
  ]
  ++ gstreamerPlugins;

  env = {
    # aws-lc-sys (rustls' crypto backend) builds with CMake instead of its prebuilt-free fallback.
    AWS_LC_SYS_CMAKE_BUILDER = 1;
    SHERPA_ONNX_LIB_DIR = "${lib.getLib sherpa-onnx}/lib";
    # Renderer gates as in upstream's public builds (`just bundle`): no Block sign-in gate,
    # bring-your-own-key providers on.
    VITE_AUTH_GATE = "0";
    VITE_BYO_KEY_PROVIDERS = "1";
    VITE_APP_VERSION = finalAttrs.version;
    BERD_APP_VERSION = finalAttrs.version;
    # Updates come from nixpkgs. Without the release overlay (tauri.release.conf.json) there is
    # no updater public key, so the backend never registers the updater; this hides its UI.
    VITE_UPDATER_ENABLED = "false";
  };

  # cmake is only used by dependency build scripts
  dontUseCmakeConfigure = true;

  buildFeatures = [
    # The app-control server the bundled berdctl CLI talks to; on in upstream releases.
    "berdctl"
    # Don't download Node.js and npm-install the Claude Code/Codex ACP bridges into the app's
    # data directory at runtime. Users install agents (e.g. claude-agent-acp) from nixpkgs.
    "no-managed-acp-tools"
    # Don't offer to symlink berdctl into /usr/local/bin; it is in $out/bin.
    "no-bb-cli-install"
  ];

  preBuild = ''
    # The frontend imports the vendored @aaif/goose-sdk from its build output (upstream's
    # `just setup` builds it before `pnpm build`).
    pnpm --filter @aaif/goose-sdk build:ts

    # berdctl and berd-monitor are sidecars too, built from the same Cargo workspace.
    (
      cd src-tauri
      cargo build --release --offline --frozen -j $NIX_BUILD_CORES \
        --target ${rustTarget} -p berdctl -p berd-monitor
    )
    for executable in berdctl berd-monitor; do
      install -Dm755 "src-tauri/target/${rustTarget}/release/$executable" \
        "src-tauri/binaries/$executable-${rustTarget}"
    done
  '';

  tauriBuildFlags = [ "--no-sign" ];

  # The app's tests need a display and a running Goose; berdctl and berd-monitor are covered
  # by passthru.tests.
  doCheck = false;

  postInstall = ''
    # The app finds its sidecars next to its own executable and its resources (distro/,
    # runtime-config.json, sounds) at ../lib/Berd relative to the executable's directory;
    # without that directory Tauri falls back to /usr/lib/Berd. Keep all of it together under
    # libexec, so $out/bin holds only `berd` and `berdctl` and not goosed, catch and
    # berd-monitor.
    mkdir -p $out/libexec/berd/bin
    mv $out/bin/* $out/libexec/berd/bin/
    mv $out/lib $out/libexec/berd/lib

    substituteInPlace $out/share/applications/Berd.desktop \
      --replace-fail 'Exec=Berd' 'Exec=berd' \
      --replace-fail 'Categories=' 'Categories=Development;Utility;'
  '';

  # Wrap only the app, not the sidecars; see postFixup.
  dontWrapGApps = true;

  preFixup = ''
    gappsWrapperArgs+=(
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
    )
  '';

  postFixup = ''
    makeWrapper $out/libexec/berd/bin/Berd $out/bin/berd "''${gappsWrapperArgs[@]}"
    # berdctl talks to a running Berd; agents started by Berd get it via BERDCTL_BIN.
    ln -s ../libexec/berd/bin/berdctl $out/bin/berdctl
  '';

  passthru = {
    tests.sidecars = runCommand "berd-sidecars-test" { } ''
      # goose writes its logs under HOME even for --help.
      export HOME=$(mktemp -d)
      for executable in Berd goosed berdctl berd-monitor catch; do
        test -x ${finalAttrs.finalPackage}/libexec/berd/bin/$executable
      done
      # Tauri's resource dir, next to the executable's directory.
      test -f ${finalAttrs.finalPackage}/libexec/berd/lib/Berd/runtime-config.json
      ${finalAttrs.finalPackage}/libexec/berd/bin/goosed serve --help | grep -q -- '--allowed-origin'
      ${finalAttrs.finalPackage}/bin/berdctl --help | grep -q 'Control the Berd desktop app'
      ${finalAttrs.finalPackage}/libexec/berd/bin/berd-monitor --help | grep -q 'Berd session'
      touch $out
    '';
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Desktop app for working with AI agents, built on Goose";
    homepage = "https://github.com/block/berd";
    changelog = "https://github.com/block/berd/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "berd";
    maintainers = [ lib.maintainers.kleinbem ];
    # Not tested on darwin yet (needs the Catch sidecar and the macOS bundle layout).
    platforms = lib.platforms.linux;
  };
})
