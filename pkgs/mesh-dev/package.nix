{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  protobuf,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "mesh-dev";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "kleinbem";
    repo = "mesh-dev-plugin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ivSHWUSMrdL00KxlKQnDK3KPpfMb5irVc0HrLRTbl6w=";
  };

  cargoHash = "sha256-Z6Yp8y+mrTPRuw2jdJvc2rv5zcv/l961dA5liBGkS8k=";

  nativeBuildInputs = [
    pkg-config
    protobuf
  ];

  checkFlags = [
    "--"
    "--test-threads=1"
  ];

  # Ship plugin metadata, declarative E2E suites, and an installable archive
  # alongside the binary so `mesh-llm plugins install --archive` and canary
  # checks can consume it straight from the Nix store.
  postInstall = ''
    mkdir -p $out/share/mesh-dev/suites
    cp plugin.toml README.md LICENSE $out/share/mesh-dev/
    cp suites/*.toml $out/share/mesh-dev/suites/
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    $out/bin/mesh-dev manifest > $out/share/mesh-dev/plugin-manifest.json
    stage=$(mktemp -d)
    mkdir -p "$stage/mesh-dev"
    cp $out/bin/mesh-dev "$stage/mesh-dev/mesh-dev"
    cp $out/share/mesh-dev/plugin.toml \
      $out/share/mesh-dev/plugin-manifest.json \
      $out/share/mesh-dev/README.md \
      $out/share/mesh-dev/LICENSE \
      "$stage/mesh-dev/"
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
      -czf $out/share/mesh-dev/mesh-dev.tar.gz -C "$stage" mesh-dev
    rm -rf "$stage"
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Zero-GPU developer and test plugin for Mesh-LLM";
    homepage = "https://github.com/kleinbem/mesh-dev-plugin";
    license = lib.licenses.asl20;
    mainProgram = "mesh-dev";
    maintainers = [ ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
