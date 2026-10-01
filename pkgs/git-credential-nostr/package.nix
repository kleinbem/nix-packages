{
  lib,
  fetchFromGitHub,
  rustPlatform,
  git,
  makeWrapper,
}:

rustPlatform.buildRustPackage {
  pname = "git-credential-nostr";
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

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];

  cargoBuildFlags = [ "--package=git-credential-nostr" ];
  cargoTestFlags = [ "--package=git-credential-nostr" ];

  preBuild = ''
    # Remap transient Nix build paths for reproducible output.
    export RUSTFLAGS="--remap-path-prefix=$NIX_BUILD_TOP=/build ''${RUSTFLAGS:-}"
    export NIX_CFLAGS_COMPILE="-ffile-prefix-map=$NIX_BUILD_TOP=/build ''${NIX_CFLAGS_COMPILE:-}"
  '';

  postInstall = ''
    wrapProgram $out/bin/git-credential-nostr \
      --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  meta = {
    description = "Git credential helper producing NIP-98 authentication headers for Nostr git repositories";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    mainProgram = "git-credential-nostr";
    maintainers = with lib.maintainers; [ ];
  };
}
