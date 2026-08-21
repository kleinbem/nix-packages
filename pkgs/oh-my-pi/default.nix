# Oh My Pi (omp, github.com/can1357/oh-my-pi) — terminal coding-agent CLI.
#
# Vendored as a prebuilt-binary derivation (same pattern as
# pkgs/antigravity/cli.nix): upstream publishes real GitHub Releases binaries
# (omp-<platform>-<arch>) rather than requiring a build from source — the
# project's own multi-stage Dockerfile (Rust/Bazel/Bun toolchain) exists for
# their own release pipeline, not as the intended way to obtain the tool.
# Hashes pinned in ./versions.json. Bump the version + re-fetch hashes with:
#   nix hash file --sri <url>
#
# NOT autoPatchelfHook: the binary is a `bun build --compile` output, which
# embeds its actual application bytecode as a fixed-offset-from-EOF trailer
# appended to the plain bun executable. patchelf rewriting the ELF interpreter
# to a (much longer) Nix store path grows the file — confirmed live
# 2026-08-05 (+2480 bytes vs the original download) — which shifts that
# trailer's expected offset and silently breaks the embedded-payload lookup:
# the binary still runs, but falls through to plain bun's own generic CLI
# instead of omp's. Wrapping with an explicit dynamic-linker invocation
# (`ld-linux-x86-64.so.2 --library-path ... <unmodified binary>`) leaves the
# original bytes completely untouched and was confirmed working.
{
  lib,
  stdenv,
  fetchurl,
  glibc,
  makeWrapper,
}:
let
  pname = "oh-my-pi";
  version = "17.4.0";
  inherit (stdenv.hostPlatform) system;

  versions = builtins.fromJSON (builtins.readFile ./versions.json);
  manifest = versions.${version}.${system} or (throw "Unsupported system for oh-my-pi: ${system}");

  dynamicLinker =
    {
      x86_64-linux = "ld-linux-x86-64.so.2";
      aarch64-linux = "ld-linux-aarch64.so.1";
    }
    .${system} or (throw "Unsupported system for oh-my-pi: ${system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (manifest) url;
    inherit (manifest) hash;
  };

  # Not an archive — the release asset IS the binary.
  dontUnpack = true;
  # stdenv's default fixupPhase strips ELF binaries even without
  # autoPatchelfHook — that alone was enough to break the embedded-payload
  # trailer (see top-of-file comment), confirmed live 2026-08-05 via a raw
  # byte comparison (e_shoff moved) even after switching away from
  # patchelf entirely.
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec
    # Untouched, byte-for-byte as downloaded — see the top-of-file comment
    # for why this must NOT go through patchelf.
    install -m755 $src $out/libexec/omp-unwrapped

    makeWrapper "${glibc}/lib/${dynamicLinker}" $out/bin/omp \
      --add-flags "--library-path ${glibc}/lib" \
      --add-flags "$out/libexec/omp-unwrapped"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Terminal coding-agent CLI — IDE capabilities (LSP, Python/JS execution, browser, subagents) wired into a single terminal tool";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "omp";
  };
}
