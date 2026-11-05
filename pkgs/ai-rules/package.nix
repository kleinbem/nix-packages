{
  lib,
  rustPlatform,
  fetchFromGitHub,
  runCommand,
  versionCheckHook,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ai-rules";
  version = "1.7.0";

  src = fetchFromGitHub {
    owner = "block";
    repo = "ai-rules";
    tag = "v${finalAttrs.version}";
    hash = "sha256-poXUcUooEZEHNLk2y4lfDspS1NRox2HvVjSPHIuCEHg=";
  };

  cargoHash = "sha256-JvE2IOig9fdBN9qNTgpwQKKfheIjx0d0h4PHRdSHDGA=";

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    tests.generate = runCommand "ai-rules-generate-test" { } ''
      export HOME=$(mktemp -d)
      mkdir -p "$HOME/project" && cd "$HOME/project"
      ${lib.getExe finalAttrs.finalPackage} init --force
      printf '# Rules\n\nAlways write tests.\n' > ai-rules/rules.md
      ${lib.getExe finalAttrs.finalPackage} generate --agents claude,goose
      # Each agent's rules file is a symlink into ai-rules/.generated-ai-rules/.
      grep -q 'Always write tests' CLAUDE.md
      grep -q 'Always write tests' AGENTS.md
      touch $out
    '';
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Manage AI rules, commands and skills across coding agents from one place";
    homepage = "https://github.com/block/ai-rules";
    changelog = "https://github.com/block/ai-rules/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "ai-rules";
    maintainers = [ lib.maintainers.kleinbem ];
    platforms = lib.platforms.unix;
  };
})
