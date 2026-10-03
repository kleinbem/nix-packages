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
  pname = "buzz-acp";
  inherit (buzzSource) version src cargoHash;

  cargoBuildFlags = [
    "--package=buzz-acp"
    "--bin=buzz-acp"
  ];

  cargoTestFlags = [
    "--package=buzz-acp"
  ];

  checkFlags = [
    "--skip=acp::tests::claude_named_adapter_wire_lifecycle_records_prompt_and_cost"
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
    description = "Agent Control Protocol (ACP) bridge for the Buzz workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-acp";
    maintainers = with lib.maintainers; [ kleinbem ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
