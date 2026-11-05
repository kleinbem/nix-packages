{
  lib,
  buildGoModule,
  fetchFromGitHub,
  runCommand,
  nix-update-script,
}:

# Upstream has no releases or tags yet; the version is the commit's date.
buildGoModule (finalAttrs: {
  pname = "codecrucible";
  version = "0-unstable-2026-10-15";

  src = fetchFromGitHub {
    owner = "block";
    repo = "codecrucible";
    rev = "b5c8086b7f7031b828b5fbcfeac53fa58b4c9a38";
    hash = "sha256-MUvLAtN4rVGxbKLBDt604YnTC0DosL5cdKGb6mzwzgQ=";
  };

  vendorHash = "sha256-ixHwMQf9cB2yWDbaxgWjobReUojj5hMMAKzZDDzG5iM=";

  # The prompt templates aren't embedded: without --prompts-dir the scanner
  # looks for prompts/default in the working directory only, which an
  # installed binary doesn't have. The patch adds a build-time default that
  # is tried after the working directory (to be proposed upstream).
  patches = [ ./installed-prompts-default.patch ];

  subPackages = [ "cmd/codecrucible" ];

  # As the Makefile does: the version shown by --version; plus the installed
  # prompt set from the patch above.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/block/codecrucible/internal/cli.version=${finalAttrs.version}"
    "-X github.com/block/codecrucible/internal/cli.defaultPromptsDir=${placeholder "out"}/share/codecrucible/prompts/default"
  ];

  postInstall = ''
    mkdir -p $out/share/codecrucible
    cp -r prompts $out/share/codecrucible/prompts
  '';

  passthru = {
    tests.cli = runCommand "codecrucible-cli-test" { } ''
      ${lib.getExe finalAttrs.finalPackage} --help | grep -qi scan
      ${lib.getExe finalAttrs.finalPackage} scan --help | grep -q -- '--provider'
      ${lib.getExe finalAttrs.finalPackage} --version | grep -q '${finalAttrs.version}'
      test -f ${finalAttrs.finalPackage}/share/codecrucible/prompts/default/feature_detection.yaml
      # init writes the commented config without needing a provider.
      cd $(mktemp -d) && ${lib.getExe finalAttrs.finalPackage} init >/dev/null && test -s .codecrucible.yaml
      touch $out
    '';
    updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };
  };

  meta = {
    description = "LLM-based security analysis of git repositories, with an audit pass and SARIF output";
    homepage = "https://github.com/block/codecrucible";
    license = lib.licenses.asl20;
    mainProgram = "codecrucible";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
