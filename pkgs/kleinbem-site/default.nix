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
    rev = "6cb0476d6044118b2077e8d06a8c0cded185aeab";
    hash = "sha256-mALgbbROP+kBEebCrWl9CL/yyi0dYOVWQR6jwxfzjn8=";
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
