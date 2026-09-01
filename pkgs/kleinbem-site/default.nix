# kleinbem.dev — Astro + Svelte + Tailwind static site (kleinbem/kleinbem-site).
# Static output only (no SSR adapter), so the derivation is just the built
# `dist/` tree — nix-config's Caddy vhost serves $out directly as its root.
#
# Bump: grab the new commit SHA from the kleinbem-site repo, then
#   nix run nixpkgs#nix-prefetch-github -- kleinbem kleinbem-site --rev <sha>
#   nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # after `git show <sha>:package-lock.json`
{
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage rec {
  pname = "kleinbem-site";
  version = "0-unstable-2026-09-01";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-site";
    rev = "bb152d7e2b6ad0c999b414fed981bc995488f160";
    hash = "sha256-6jhUm/r6yKVChHwER+Ibab+UKUb/sEtj7EXeqon3eV8=";
  };

  npmDepsHash = "sha256-1QxLbK8fbCv2zUkY9OtB3jEj9t8qX97cxFhFir6r58Q=";

  nodejs = nodejs_22;

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';

  meta = {
    description = "kleinbem.dev — personal site (Astro + Svelte + Tailwind, static output)";
    homepage = "https://github.com/kleinbem/kleinbem-site";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
