# kleinbem-auth — better-auth social-login service for kleinbem.dev
# (kleinbem/kleinbem-auth). TypeScript → tsc → dist/, run under plain node.
#
# NOT yet wired into ../../default.nix — the GitHub repo doesn't exist until
# github-config PR #3 is merged. To finish:
#   1. Merge github-config PR #3, wait for the repo to be created, push the
#      local kleinbem-auth git repo to it.
#   2. Fill rev + hash:
#        nix run nixpkgs#nix-prefetch-github -- kleinbem kleinbem-auth --rev <sha>
#   3. Fill npmDepsHash:
#        git -C ../kleinbem-auth show <sha>:package-lock.json > /tmp/pl.json
#        nix run nixpkgs#prefetch-npm-deps -- /tmp/pl.json
#   4. Uncomment the `kleinbem-auth = pkgs.callPackage ./pkgs/kleinbem-auth { };`
#      line in ../../default.nix.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  python3,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "kleinbem-auth";
  version = "0-unstable-2026-09-03";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-auth";
    rev = "0000000000000000000000000000000000000000"; # TODO: real SHA
    hash = lib.fakeHash; # TODO: nix-prefetch-github
  };

  npmDepsHash = lib.fakeHash; # TODO: prefetch-npm-deps package-lock.json

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
