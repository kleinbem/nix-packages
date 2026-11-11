{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cacert,
  stdenv,
  pkg-config,
  aws-lc,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };
in
rustPlatform.buildRustPackage {
  pname = "buzz-cli";
  inherit (buzzSource) version src cargoHash;

  cargoBuildFlags = [
    "--package=buzz-cli"
    "--bin=buzz"
  ];

  cargoTestFlags = [
    "--package=buzz-cli"
  ];

  # nixpkgs makes aws-lc-sys link the system AWS-LC (AWS_LC_SYS_USE_SYSTEM=1).
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ aws-lc ];

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
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
