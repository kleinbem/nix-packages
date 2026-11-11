{
  lib,
  fetchFromGitHub,
  rustPlatform,
  bash,
  git,
  makeWrapper,
  ripgrep,
  pkg-config,
  aws-lc,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };
in
rustPlatform.buildRustPackage {
  pname = "buzz-dev-mcp";
  inherit (buzzSource) version src cargoHash;

  patches = [
    # Fix BIP-340 curve point validation under nostr 0.44 (upstream block/buzz#6175)
    ./fix-bip340-pubkey-validation.patch
  ];

  # nixpkgs makes aws-lc-sys link the system AWS-LC (AWS_LC_SYS_USE_SYSTEM=1).
  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];
  buildInputs = [ aws-lc ];
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
