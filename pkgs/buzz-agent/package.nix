{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cacert,
  stdenv,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };
in
rustPlatform.buildRustPackage {
  pname = "buzz-agent";
  inherit (buzzSource) version src cargoHash;

  cargoBuildFlags = [
    "--package=buzz-agent"
    "--bin=buzz-agent"
  ];

  cargoTestFlags = [
    "--package=buzz-agent"
  ];

  nativeCheckInputs = [ cacert ];

  env = lib.optionalAttrs (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) {
    # Avoid nondeterministic LC_UUIDs emitted by ld64 on arm64.
    RUSTFLAGS = "-C link-arg=-Wl,-no_uuid";
  };

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  postInstall = ''
    # Remove test-only binaries if any were installed
    rm -f $out/bin/fake-mcp $out/bin/lock-holder $out/bin/auth-worker
  '';

  meta = {
    description = "Minimal, unbreakable ACP-compliant agent for the Buzz workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-agent";
    maintainers = with lib.maintainers; [ kleinbem ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
