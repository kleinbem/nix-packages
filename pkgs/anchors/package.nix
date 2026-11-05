{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  coreutils,
  curl,
  findutils,
  git,
  gnugrep,
  gnused,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "anchors";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "block";
    repo = "anchorsmd";
    tag = finalAttrs.version;
    hash = "sha256-s/NqVG3UdzX4WDd6eswFrDeiCtngKuKYhsFHgiXwFio=";
  };

  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  # The tests run the script directly, and its #!/bin/bash doesn't exist in
  # the sandbox (the install output is patched by fixupPhase anyway).
  postPatch = ''
    patchShebangs anchors test
  '';

  # The upstream test suite drives the CLI against fixtures.
  doCheck = true;
  nativeCheckInputs = [
    git
    gnugrep
    gnused
  ];
  checkPhase = ''
    runHook preCheck
    HOME=$(mktemp -d) bash test/run.sh
    runHook postCheck
  '';

  # The script finds the skill it installs next to itself (SCRIPT_DIR/skill),
  # following symlinks, so keep both together under libexec.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/anchors $out/bin
    cp anchors $out/libexec/anchors/anchors
    cp -r skill $out/libexec/anchors/skill
    chmod 755 $out/libexec/anchors/anchors
    makeWrapper $out/libexec/anchors/anchors $out/bin/anchors \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          curl
          findutils
          git
          gnugrep
          gnused
        ]
      }
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "CLI for ANCHORS, requirements-driven development for AI agents";
    homepage = "https://github.com/block/anchorsmd";
    changelog = "https://github.com/block/anchorsmd/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "anchors";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
