{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  pkg-config,
  python3,
  cairo,
  giflib,
  libjpeg,
  libpng,
  librsvg,
  pango,
  pixman,
  makeWrapper,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "bgutil-ytdlp-pot-provider-server";
  version = "2.0.2";

  src = fetchFromGitHub {
    owner = "Brainicism";
    repo = "bgutil-ytdlp-pot-provider";
    tag = finalAttrs.version;
    hash = "sha256-rV85jle5R8je7iR8uZaXEdDuQEh2lf/Eoht+9k6bpC4=";
  };

  sourceRoot = "${finalAttrs.src.name}/server";

  npmDepsHash = "sha256-Ffse1RelOmLpfYM50zZ/xqkfy9l2TGYE8CumK0b9cQg=";

  # canvas builds its native module from source (no prebuilt download in the sandbox).
  nativeBuildInputs = [
    pkg-config
    python3
    makeWrapper
  ];
  buildInputs = [
    cairo
    giflib
    libjpeg
    libpng
    librsvg
    pango
    pixman
  ];

  dontNpmBuild = true;
  buildPhase = ''
    runHook preBuild
    npx tsc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    npm prune --omit=dev --no-audit --no-fund
    # Intermediate objects of canvas' native build; only the .node files are used.
    rm -rf node_modules/canvas/build/Release/obj.target
    mkdir -p $out/lib/bgutil-pot-server
    cp -r build node_modules package.json $out/lib/bgutil-pot-server/
    makeWrapper ${lib.getExe nodejs} $out/bin/bgutil-pot-server \
      --add-flags $out/lib/bgutil-pot-server/build/main.js
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Proof-of-origin token server for yt-dlp (used by Music Assistant's YouTube Music provider)";
    homepage = "https://github.com/Brainicism/bgutil-ytdlp-pot-provider";
    license = lib.licenses.gpl3Only;
    mainProgram = "bgutil-pot-server";
    platforms = lib.platforms.linux;
  };
})
