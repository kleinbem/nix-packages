{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bash,
  jdk21,
  android-tools,
  coreutils,
  esbuild,
  ffmpeg,
  jq,
  libwebp,
  runCommand,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "trailblaze";
  version = "2026.10.30";

  # Upstream ships the CLI as an uber JAR plus a bash launcher (its Homebrew
  # formula installs the same two files). A build from the Kotlin/Gradle
  # sources is the next step for nixpkgs.
  src = fetchurl {
    url = "https://github.com/block/trailblaze/releases/download/v${finalAttrs.version}/trailblaze.jar";
    hash = "sha256-AhjFGTVHCjHClqa45vFeAqZGm6zhG3sbEh/qKztZtp8=";
  };

  launcher = fetchurl {
    url = "https://github.com/block/trailblaze/releases/download/v${finalAttrs.version}/trailblaze";
    hash = "sha256-pHFJvpFIPoFmLT60P5Ipcr2ongRCOqYLM1FdPTM0LeA=";
  };

  dontUnpack = true;
  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  # The launcher expects the JAR next to itself, honours JAVA_HOME, and uses
  # jq for its daemon fast path; ffmpeg, esbuild and webp render the trail
  # recordings, adb talks to Android devices.
  installPhase = ''
    runHook preInstall
    install -Dm644 $src $out/libexec/trailblaze/trailblaze.jar
    install -Dm755 $launcher $out/libexec/trailblaze/trailblaze
    makeWrapper $out/libexec/trailblaze/trailblaze $out/bin/trailblaze \
      --set-default JAVA_HOME ${jdk21.home} \
      --prefix PATH : ${
        lib.makeBinPath [
          android-tools
          coreutils
          esbuild
          ffmpeg
          jq
          libwebp
        ]
      }
    runHook postInstall
  '';

  passthru = {
    tests.help = runCommand "trailblaze-help-test" { } ''
      export HOME=$(mktemp -d)
      ${lib.getExe finalAttrs.finalPackage} --help 2>&1 | grep -qi 'trail'
      touch $out
    '';
    # The launcher is a second release asset with its own hash.
    updateScript = nix-update-script {
      extraArgs = [
        "--custom-dep"
        "launcher"
      ];
    };
  };

  meta = {
    description = "AI-driven UI testing framework for Android, iOS and web that records trails";
    homepage = "https://github.com/block/trailblaze";
    changelog = "https://github.com/block/trailblaze/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    mainProgram = "trailblaze";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
