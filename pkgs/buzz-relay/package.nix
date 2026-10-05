{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cmake,
  pkg-config,
  perl,
  protobuf,
  openssl,
  git,
  bash,
  makeWrapper,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };
in
rustPlatform.buildRustPackage {
  pname = "buzz-relay";
  inherit (buzzSource) version src cargoHash;

  postPatch = ''
    substituteInPlace crates/buzz-relay/src/api/git/hook.rs \
      --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe bash}'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    perl
    protobuf
    makeWrapper
  ];

  buildInputs = [ openssl ];

  # cmake is only used by dependency build scripts; avoid overriding cargo configurePhase
  dontUseCmakeConfigure = true;

  cargoBuildFlags = [
    "--package=buzz-relay"
    "--package=buzz-admin"
    "--package=buzz-pair-relay"
  ];

  # Full workspace tests require live Postgres, Redis, and S3 services
  doCheck = false;

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  postInstall = ''
    wrapProgram $out/bin/buzz-relay \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          bash
        ]
      }
  '';

  meta = {
    description = "Relay server, admin CLI, and pairing relay for the Buzz decentralized workspace";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "buzz-relay";
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
