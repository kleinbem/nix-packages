{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeBinaryWrapper,
  git,
  goose-cli,
  runCommand,
  nix-update-script,
}:

# Upstream has no releases or tags yet; the version is the commit's date.
buildGoModule (finalAttrs: {
  pname = "block-review";
  version = "0-unstable-2026-10-11";

  src = fetchFromGitHub {
    owner = "block";
    repo = "review";
    rev = "0c13293f6f2dff3ee859bca29dd9b815da4314bf";
    hash = "sha256-AFVC7MngBNl8QEE8tKOEwxujcnU4EOJyb7ckteEgC+4=";
  };

  # Standard library only.
  vendorHash = null;

  subPackages = [ "cmd/review" ];

  ldflags = [
    "-s"
    "-w"
  ];

  nativeBuildInputs = [ makeBinaryWrapper ];

  # Every review pass is a `goose run` over a git range.
  postInstall = ''
    wrapProgram $out/bin/review --prefix PATH : ${
      lib.makeBinPath [
        git
        goose-cli
      ]
    }
  '';

  passthru = {
    tests.usage = runCommand "block-review-usage-test" { } ''
      # No arguments prints the usage and exits non-zero.
      if ${lib.getExe finalAttrs.finalPackage} > out 2>&1; then exit 1; fi
      grep -qi 'review' out
      ${lib.getExe finalAttrs.finalPackage} review -h 2>&1 | grep -q -- '-base'
      touch $out
    '';
    updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };
  };

  meta = {
    description = "LLM code reviewer for git changes built on Goose, with panelists, a coordinator and a judge";
    homepage = "https://github.com/block/review";
    license = lib.licenses.asl20;
    mainProgram = "review";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
