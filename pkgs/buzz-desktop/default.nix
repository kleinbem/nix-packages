{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchPnpmDeps,
  callPackage,
  cargo-tauri,
  cmake,
  perl,
  pkg-config,
  nodejs_24,
  pnpm_11,
  pnpmConfigHook,
  wrapGAppsHook3,
  makeShellWrapper,
  alsa-lib,
  gtk3,
  libopus,
  libsoup_3,
  webkitgtk_4_1,
  glib-networking,
  gst_all_1,
  onnxruntime,
  sherpa-onnx,
  vulkan-loader,
  bash,
  git,
  ffmpeg-headless,
  cacert,
  coreutils,
  nix-update-script,
}:

let
  pnpm = pnpm_11.override {
    nodejs-slim = nodejs_24;
  };

  rustTarget = stdenv.hostPlatform.rust.rustcTarget;

  gstreamerPlugins = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
    # transcode elements for WebKit's MediaRecorder (voice notes)
    gst-plugins-bad
    gst-libav
  ];

  # Keep the GStreamer plugin registry per user and per target, so it is not
  # shared with (and corrupted by) other GStreamer applications.
  registrySetup = ''
    if [[ -z "''${GST_REGISTRY_1_0:-}" ]]; then
      cacheHome="''${XDG_CACHE_HOME:-''${HOME:?HOME must be set}/.cache}"
      export GST_REGISTRY_1_0="$cacheHome/buzz/gstreamer-1.0/registry-${rustTarget}.bin"
      ${coreutils}/bin/mkdir -p "$cacheHome/buzz/gstreamer-1.0"
    fi
  '';
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "buzz-desktop";
  version = "0.5.26";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    tag = "desktop-v${finalAttrs.version}";
    hash = "sha256-w/CHknkyFT+iHv4jd5Anv1Q/5kOZ7H1DEKB9dwqQHiE=";
  };

  cargoRoot = "desktop/src-tauri";
  buildAndTestSubdir = "desktop/src-tauri";
  cargoHash = "sha256-GQoRKRv0eM94ckLPBsMWHwA3tPqpThm8ZDv0DL4RUZQ=";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-qxtgbCeivfpAQg2+JOUGCQo7agf0GAARvLle89jFzu4=";
  };
  pnpmWorkspaces = [ "buzz" ];

  postPatch = ''
    mkdir -p desktop/src-tauri/binaries
    for executable in \
      buzz \
      buzz-acp \
      buzz-agent \
      buzz-backend-kubernetes \
      buzz-dev-mcp \
      git-credential-nostr
    do
      install -Dm755 \
        "${finalAttrs.passthru.sidecars}/bin/$executable" \
        "desktop/src-tauri/binaries/$executable-${rustTarget}"
    done

    # Link against sherpa-onnx from nixpkgs instead of downloading prebuilt static libraries.
    # Every dependent must opt out of the default `static` feature, or Cargo unifies both.
    for manifest in desktop/src-tauri/Cargo.toml crates/buzz-voice/Cargo.toml; do
      substituteInPlace "$manifest" \
        --replace-fail 'sherpa-onnx = "1.12"' \
          'sherpa-onnx = { version = "1.12", default-features = false, features = [ "shared" ] }'
    done
  '';

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
    cargo-tauri.hook
    nodejs_24
    pnpm
    pnpmConfigHook
    wrapGAppsHook3
    makeShellWrapper
  ];

  buildInputs = [
    alsa-lib
    gtk3
    libopus
    libsoup_3
    webkitgtk_4_1
    glib-networking
    onnxruntime
    sherpa-onnx
  ]
  ++ gstreamerPlugins;

  env = {
    AWS_LC_SYS_CMAKE_BUILDER = 1;
    SHERPA_ONNX_LIB_DIR = "${lib.getLib sherpa-onnx}/lib";
  };

  # cmake is only used by dependency build scripts
  dontUseCmakeConfigure = true;

  cargoBuildFlags = [
    "--package"
    "buzz-desktop"
  ];

  # Compute sharing; upstream's Linux release builds enable it too.
  buildFeatures = [ "mesh-llm" ];

  doNotPostBuildInstallCargoBinaries = true;
  tauriBuildFlags = [ "--no-sign" ];

  # The desktop crate's tests need a display and a running relay; the bundled
  # sidecars are tested in their standalone packages (buzz-agent, buzz-dev-mcp, ...).
  doCheck = false;

  postInstall = ''
    # The app finds its sidecars next to its own executable. Keep them out of
    # $out/bin so they don't collide with the standalone buzz-cli, buzz-agent, etc.
    mkdir -p $out/libexec/buzz-desktop
    mv $out/bin/* $out/libexec/buzz-desktop/

    substituteInPlace $out/share/applications/Buzz.desktop \
      --replace-fail 'Categories=' 'Categories=Network;Chat;InstantMessaging;'
    ln -s Buzz.desktop $out/share/applications/buzz-desktop.desktop
  '';

  # Wrap only the app (not the sidecars), in one shell wrapper; see postFixup.
  dontWrapGApps = true;

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : "${
        lib.makeBinPath [
          bash
          git
          ffmpeg-headless
        ]
      }"
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
      --set-default BUZZ_SHELL "${lib.getExe bash}"
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${lib.makeSearchPath "lib/gstreamer-1.0" gstreamerPlugins}"
      # mesh-llm downloads prebuilt llama.cpp runtimes (CPU or Vulkan) and dlopens
      # them; libgomp and libvulkan are not on any default path on NixOS.
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          stdenv.cc.cc.lib
          vulkan-loader
        ]
      }"
    )
  '';

  # A shell wrapper because the registry path depends on $HOME at runtime (`--run`).
  postFixup = ''
    makeShellWrapper "$out/libexec/buzz-desktop/buzz-desktop" "$out/bin/buzz-desktop" \
      "''${gappsWrapperArgs[@]}" \
      --run ${lib.escapeShellArg registrySetup}
  '';

  passthru = {
    # Built from the same tag as the app so the bundled binaries match it.
    sidecars = callPackage ./sidecars.nix {
      inherit (finalAttrs) version src;
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "desktop-v(.*)"
        "--subpackage"
        "sidecars"
      ];
    };
  };

  meta = {
    description = "Desktop client for Buzz, a Nostr-based workspace";
    homepage = "https://github.com/block/buzz";
    changelog = "https://github.com/block/buzz/releases/tag/desktop-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "buzz-desktop";
    maintainers = [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
