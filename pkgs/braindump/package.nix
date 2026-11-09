{
  lib,
  buildGoModule,
  fetchFromGitHub,
  runCommand,
  nix-update-script,
}:

# Upstream has no releases or tags yet; the version is the commit's date.
buildGoModule (finalAttrs: {
  pname = "braindump";
  version = "0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "block";
    repo = "braindump";
    rev = "9e61e4101c053a29082c9437bdf0d6408e33ff8b";
    hash = "sha256-0FcbR+sPELxcVNYlQieIbJYuNcjjhC+kU096FYCtJwc=";
  };

  vendorHash = "sha256-gM8vBy+1fKOOEh5MUIFJHqtGFp4QZrECF+ZWcIsQ7Ew=";

  subPackages = [ "cmd/braindump" ];

  ldflags = [
    "-s"
    "-w"
  ];

  passthru = {
    tests.empty-home = runCommand "braindump-empty-home-test" { } ''
      # No agent sessions anywhere: the dump is an empty JSON array.
      export HOME=$(mktemp -d)
      ${lib.getExe finalAttrs.finalPackage} --help | grep -qi session
      ${lib.getExe finalAttrs.finalPackage} > out
      grep -q '^\[\]' out || grep -q 'null' out
      touch $out
    '';
    updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };
  };

  meta = {
    description = "Dumps Claude Code and goose agent session histories as one JSON format";
    homepage = "https://github.com/block/braindump";
    license = lib.licenses.asl20;
    mainProgram = "braindump";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
