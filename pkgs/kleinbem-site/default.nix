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
  version = "0-unstable-2026-09-13";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "kleinbem-site";
    rev = "1b5b65225581f7b85e1d42378b17cd13988f19d9";
    hash = "sha256-GEYrtd88UT7Fx2dbg3Hwz0XOT2wc2Swtd8MiHVawhss=";
  };

  npmDepsHash = "sha256-in7V4qXGrNsqsEU0Y4QMXk2VnlJU2FQjqNWWVuDykXA=";

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
