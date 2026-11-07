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

buildGoModule (finalAttrs: {
  pname = "block-review";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "block";
    repo = "review";
    tag = "v${finalAttrs.version}";
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
    updateScript = nix-update-script { };
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
