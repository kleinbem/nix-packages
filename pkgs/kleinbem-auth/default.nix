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
  version = "0-unstable-2026-09-12";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-auth";
    rev = "a87e94bce6a06641bb0b96b5660bf5a820ba0aa8";
    hash = "sha256-R/hFANIQdYXHD7yjFGpv+SaVyR1QT60bZnCn1EmFDrQ=";
  };

  npmDepsHash = "sha256-WyMgydHdior4p9rZz6z+I+dR6qnDVwUWqgoXtvE+HBU=";

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
