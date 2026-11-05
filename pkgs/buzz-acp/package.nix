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
    # Tests execute fixture scripts with hardcoded `#!/usr/bin/env python3` or `#!/bin/bash`,
    # which fail inside the isolated Nix build sandbox where those paths/binaries do not exist.
    "--skip=acp::launch::tests::wrapper_preserves_worker_identity_and_runs_on_each_spawn"
    "--skip=pool::pi_prompt_tests::pi_composed_prompt_uses_meta_without_capability_negotiation"
    "--skip=pool::pi_prompt_tests::pi_launch_preserves_existing_skills_in_explicit_workspace"
    "--skip=pool::pi_prompt_tests::upstream_pi_acp_launch_does_not_receive_managed_skills"
    # Integration tests execute `buzz-acp` via `.env_clear()`, stripping `SSL_CERT_FILE`
    # and expecting `git` on PATH.
    "--skip=harness_native_git_and_startup_shutdown_cleanup"
    "--skip=task_native_git_and_startup_shutdown_cleanup"
    # Integration tests in run_task spawn an external python mock agent (`tests/fixtures/task_agent.py`)
    # that invokes `git config` and requires python3 and git.
    "--skip=deadline_covers_initialize_session_and_turn_and_cleans_descendants"
    "--skip=file_and_stdin_run_one_fresh_equipped_session_without_service"
    "--skip=launch_prefix_wraps_the_shipped_local_task_entrypoint"
    "--skip=memory_is_loaded_before_session_and_opt_out_makes_no_request"
    "--skip=signals_cancel_startup_turn_and_pending_stdin_without_hanging"
    "--skip=stop_reasons_failures_and_permission_exchange_are_explicit"
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
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
