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

  checkFlags = [
    # Test executes the `buzz-agent` binary via `.env_clear()`, which strips `SSL_CERT_FILE`
    # and fails TLS root initialization inside the Nix build sandbox.
    "--skip=cli_signin_aliases_reuse_legacy_cache_without_runtime_configuration"
    # Racy: stop reading at the prompt response before the steer rejection arrives.
    # https://github.com/block/buzz/pull/8091
    "--skip=steer_rejected_on_run_id_mismatch"
    "--skip=steer_rejected_on_empty_prompt"
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
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
