{
  lib,
  fetchFromGitHub,
  rustPlatform,
  git,
  makeWrapper,
}:

let
  buzzSource = import ../buzz/source.nix { inherit fetchFromGitHub; };
in
rustPlatform.buildRustPackage {
  pname = "git-credential-nostr";
  inherit (buzzSource) version src cargoHash;

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
