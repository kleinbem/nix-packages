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
  version = "0-unstable-2026-04-29";

  src = fetchFromGitHub {
    owner = "block";
    repo = "braindump";
    rev = "d267ace6b39a5c2a12657915cb4b4a9379f76386";
    hash = "sha256-HBCOeiwuXHc2l+Bz3dKhTjVnXwKNBEs7IHTzqC7SkzI=";
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
