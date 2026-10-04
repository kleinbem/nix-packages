{
  lib,
  stdenvNoCC,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  nodejs_24,
  fetchFromGitHub,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };

  pnpm = pnpm_11.override {
    nodejs-slim = nodejs_24;
  };

  pnpmDeps = fetchPnpmDeps {
    pname = "buzz-desktop-frontend";
    inherit (buzzSource) version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-qxtgbCeivfpAQg2+JOUGCQo7agf0GAARvLle89jFzu4=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "buzz-desktop-frontend";
  inherit (buzzSource) version src;
  inherit pnpmDeps;
  strictDeps = true;

  pnpmWorkspaces = [ "buzz" ];

  nativeBuildInputs = [
    nodejs_24
    pnpm
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm --filter buzz build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R desktop/dist/. "$out/"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -f "$out/index.html"
  '';

  meta = {
    description = "Web frontend for Buzz Desktop";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
  };
}
