{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
  runCommand,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "aittributor";
  version = "0.8.1";

  src = fetchFromGitHub {
    owner = "block";
    repo = "aittributor";
    tag = "v${finalAttrs.version}";
    hash = "sha256-reSu2Yw/VufghncxXy+lAFfDluba2Ajr/9n9g49tWGI=";
  };

  cargoHash = "sha256-pGXljkb7Ytpk0oHe9gtRlNrsvxnd71P3N0j9aTPb3tA=";

  # The tests create git repositories to read the commit message from.
  nativeCheckInputs = [ git ];

  # No versionCheckHook: upstream's Cargo.toml still says 0.4.0 at every tag
  # (the release workflow doesn't bump it), so `--version` disagrees with
  # the tag. Reported upstream.

  passthru = {
    tests.hook = runCommand "aittributor-hook-test" { nativeBuildInputs = [ git ]; } ''
      export HOME=$(mktemp -d)
      cd "$HOME"
      git init -q repo && cd repo
      git config user.email test@example.com && git config user.name test
      printf 'feat: something\n' > msg
      # An agent's own environment variable is the first detection path; Cline
      # is the one agent in the table that sets one (CLINE_ACTIVE=true).
      CLINE_ACTIVE=true ${lib.getExe finalAttrs.finalPackage} msg
      grep -q '^Co-authored-by: Cline <noreply@cline.bot>' msg
      # Without an agent the message stays as it is.
      printf 'feat: something\n' > plain
      ${lib.getExe finalAttrs.finalPackage} plain
      test "$(wc -l < plain)" = 1
      touch $out
    '';
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Git prepare-commit-msg hook that adds AI agent attribution to commits";
    homepage = "https://github.com/block/aittributor";
    changelog = "https://github.com/block/aittributor/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "aittributor";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
