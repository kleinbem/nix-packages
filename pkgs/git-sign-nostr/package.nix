{
  lib,
  fetchFromGitHub,
  rustPlatform,
  git,
  makeWrapper,
}:

rustPlatform.buildRustPackage {
  pname = "git-sign-nostr";
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
  nativeCheckInputs = [ git ];

  cargoBuildFlags = [ "--package=git-sign-nostr" ];
  cargoTestFlags = [ "--package=git-sign-nostr" ];

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  postInstall = ''
    wrapProgram $out/bin/git-sign-nostr \
      --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  meta = {
    description = "NIP-GS git commit/tag signing program using Nostr secp256k1 keys";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "git-sign-nostr";
    maintainers = with lib.maintainers; [ ];
  };
}
