{
  lib,
  rustPlatform,
  cmake,
  perl,
  pkg-config,
  openssl,
  src,
  version,
}:

rustPlatform.buildRustPackage {
  pname = "buzz-desktop-sidecars";
  inherit version src;

  cargoHash = "sha256-A/lpudjM3ZahSNiWHxW8UKFlBhdBuAEQL87c8Q+C7Q4=";

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ];

  buildInputs = [ openssl ];

  dontUseCmakeConfigure = true;

  cargoBuildFlags = [
    "--bin=buzz"
    "--bin=buzz-acp"
    "--bin=buzz-agent"
    "--bin=buzz-backend-kubernetes"
    "--bin=buzz-dev-mcp"
    "--bin=git-credential-nostr"
  ];

  doCheck = false;

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
  '';

  meta = {
    description = "Bundled sidecar binaries for Buzz Desktop";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
  };
}
