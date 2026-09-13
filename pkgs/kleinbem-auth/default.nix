# kleinbem-auth — better-auth social-login service for kleinbem.dev
# (kleinbem/kleinbem-auth). TypeScript → tsc → dist/, run under plain node.
#
# Bump: grab the new commit SHA from the kleinbem-auth repo, then
#   nix run nixpkgs#nix-prefetch-github -- kleinbem kleinbem-auth --rev <sha>
#   git -C ../kleinbem-auth show <sha>:package-lock.json > /tmp/pl.json
#   nix run nixpkgs#prefetch-npm-deps -- /tmp/pl.json    # → npmDepsHash
{
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "kleinbem-auth";
  version = "0-unstable-2026-09-13.1";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-auth";
    rev = "4af900ce52911a0ccc83cceae18809e6a45676c4";
    hash = "sha256-iQZ3axLa1zSrZVWcAMHLmDFiq8D/7lMViCyAGw/BzBA=";
  };

  npmDepsHash = "sha256-0Pr+PJgB3Ad1hGBKFb0lXDwQXLWYj5F9BJ1n0OY4xSo=";

  nodejs = nodejs_22;

  # better-sqlite3 builds a native addon via node-gyp.
  nativeBuildInputs = [
    python3
    makeWrapper
  ];

  npmBuildScript = "build"; # tsc → dist/

  # Ship dist/ + runtime node_modules; expose two entrypoints with node on PATH.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/kleinbem-auth
    cp -r dist package.json node_modules $out/lib/kleinbem-auth/

    makeWrapper ${nodejs_22}/bin/node $out/bin/kleinbem-auth \
      --add-flags $out/lib/kleinbem-auth/dist/server.js

    makeWrapper ${nodejs_22}/bin/node $out/bin/kleinbem-auth-migrate \
      --add-flags $out/lib/kleinbem-auth/dist/migrate.js

    runHook postInstall
  '';

  meta = {
    description = "Self-hosted better-auth social login for kleinbem.dev";
    homepage = "https://github.com/kleinbem/kleinbem-auth";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "kleinbem-auth";
  };
}
