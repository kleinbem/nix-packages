{
  lib,
  fetchFromGitHub,
  rustPlatform,
  bash,
  git,
  makeWrapper,
  ripgrep,
}:

rustPlatform.buildRustPackage {
  pname = "buzz-dev-mcp";
  version = "0.1.0-unstable-2026-09-02";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "block";
    repo = "buzz";
    rev = "47d068e2109d077414cbf2f4f1c927f6d051037a";
    hash = "sha256-sLIyStOy330KzzVF9QnIn27loT5QXCRz0U4NN9bxU40=";
  };

  cargoHash = "sha256-q8FUmTHnPfy/Ub+TNs3UK3exOoX1GdZGwHkH5pDteKE=";

  patches = [
    # Fix BIP-340 curve point validation under nostr 0.44 (upstream issue #6175)
    ./fix-bip340-pubkey-validation.patch
  ];

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    bash
    git
    ripgrep
  ];

  cargoBuildFlags = [ "--package=buzz-dev-mcp" ];
  cargoTestFlags = [ "--package=buzz-dev-mcp" ];

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  postInstall = ''
    wrapProgram $out/bin/buzz-dev-mcp \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          git
          ripgrep
        ]
      }
  '';

  meta = {
    description = "Model Context Protocol (MCP) server for Buzz developers and AI coding agents";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-dev-mcp";
    maintainers = with lib.maintainers; [ ];
  };
}
