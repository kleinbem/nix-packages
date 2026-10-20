{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeBinaryWrapper,
  git,
  lefthook,
  runCommand,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "lhm";
  version = "0.14.1";

  src = fetchFromGitHub {
    owner = "block";
    repo = "lhm";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mvNy90iTLKf7GFbu3o6LKyqb4KwKxx8FKX68+31mLXI=";
  };

  cargoHash = "sha256-oyJjXhMiYxynsyUFiBT4qc8siRwZDZg3XJmofDIHuFs=";

  nativeBuildInputs = [ makeBinaryWrapper ];

  # The integration tests create git repositories and run the merged hooks.
  nativeCheckInputs = [
    git
    lefthook
  ];

  # lhm runs git and hands the merged config to lefthook; neither is a
  # library dependency, so put them on its PATH.
  postInstall = ''
    wrapProgram $out/bin/lhm --prefix PATH : ${
      lib.makeBinPath [
        git
        lefthook
      ]
    }
  '';

  # No versionCheckHook: upstream's Cargo.toml says 0.1.0 at every tag (the
  # release workflow doesn't bump it), so `--version` disagrees with the tag.
  # Reported upstream.

  passthru = {
    tests.dry-run = runCommand "lhm-dry-run-test" { nativeBuildInputs = [ git ]; } ''
      export HOME=$(mktemp -d)
      mkdir -p "$HOME/.config"
      printf 'pre-commit:\n  commands:\n    user-check:\n      run: true\n' > "$HOME/.config/lefthook.yaml"
      git init -q "$HOME/repo" && cd "$HOME/repo"
      printf 'pre-commit:\n  commands:\n    repo-check:\n      run: true\n' > lefthook.yaml
      ${lib.getExe finalAttrs.finalPackage} dry-run > merged
      grep -q user-check merged
      grep -q repo-check merged
      touch $out
    '';
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Merges system, user and repository lefthook configurations into one set of git hooks";
    homepage = "https://github.com/block/lhm";
    changelog = "https://github.com/block/lhm/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "lhm";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
