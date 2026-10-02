{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cacert,
  stdenv,
}:

rustPlatform.buildRustPackage {
  pname = "buzz-cli";
  version = "0.1.0-unstable-2026-09-02";

  __structuredAttrs = true;
  __darwinAllowLocalNetworking = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    rev = "47d068e2109d077414cbf2f4f1c927f6d051037a";
    hash = "sha256-sLIyStOy330KzzVF9QnIn27loT5QXCRz0U4NN9bxU40=";
  };

  cargoHash = "sha256-q8FUmTHnPfy/Ub+TNs3UK3exOoX1GdZGwHkH5pDteKE=";

  cargoBuildFlags = [
    "--package=buzz-cli"
    "--bin=buzz"
  ];

  cargoTestFlags = [
    "--package=buzz-cli"
  ];

  nativeCheckInputs = [ cacert ];

  env = lib.optionalAttrs (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) {
    RUSTFLAGS = "-C link-arg=-Wl,-no_uuid";
  };

  preBuild = ''
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  meta = {
    description = "Agent-first CLI for the Buzz relay and workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz";
    maintainers = with lib.maintainers; [ kleinbem ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
