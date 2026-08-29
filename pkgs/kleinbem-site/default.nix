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
  version = "0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-site";
    rev = "1083e05810d0bca6a69c09ecb02df4821f76c6f1";
    hash = "sha256-fmVL7cfItRQ5aEKn6j4ivp2fpf2Pf39fYaYBegjAMAk=";
  };

  npmDepsHash = "sha256-b4nef6C8z2KifCNhc1A7bQi0044GuWfY1YdtZYBvAME=";

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
