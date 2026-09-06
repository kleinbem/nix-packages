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
  version = "0-unstable-2026-09-06";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-site";
    rev = "60cdcfe4b74c7a81542203c6268b963f2cda64fa";
    hash = "sha256-GsWSts58dPYjHJtDxLyX3DLN1o1iXx7chM1C5UsEKIc=";
  };

  npmDepsHash = "sha256-//DutZHM75KJbHmhAdO47xueD3nx7jMookm7dtWHmd0=";

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
