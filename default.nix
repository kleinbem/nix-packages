# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

{
  pkgs ? import (builtins.getFlake "nixpkgs") { system = "x86_64-linux"; },
  # The flake passes its input; plain imports (overlay.nix, nix-holds-fleet)
  # take the commit in flake.lock.
  nix-holds ?
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      locked = lock.nodes.${lock.nodes.root.inputs.nix-holds}.locked;
    in
    builtins.fetchTarball {
      url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
      sha256 = locked.narHash;
    },
}:

# Packages from our open nixpkgs PRs (nixpkgs-prs.json, built by nix-holds).
(import "${nix-holds}/prs.nix" {
  inherit (pkgs) lib;
  prs = ./nixpkgs-prs.json;
}).packages
  pkgs
// {
  langfuse = pkgs.callPackage ./pkgs/langfuse { };
  ricoh-driver = pkgs.callPackage ./pkgs/ricoh-driver/default.nix { };

  # kleinbem.dev — see pkgs/kleinbem-site/default.nix header for the bump
  # procedure (pinned to a commit SHA, same pattern as langfuse above).
  kleinbem-site = pkgs.callPackage ./pkgs/kleinbem-site { };

  # Google Antigravity 2.0 — vendored from the audited jacopone derivation,
  # binaries pinned to Google's official CDNs in pkgs/antigravity/versions.json.
  # NOTE: namespaced under `google-antigravity*` to avoid clobbering nixpkgs'
  # own `antigravity` attr (which derives `antigravity-fhs = antigravity.fhs`).
  google-antigravity = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity 2.0";
  };
  google-antigravity-ide = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity IDE";
  };
  # no-FHS variant: autoPatchelf instead of bubblewrap, so `sudo` works in the
  # integrated terminal (FHS sandbox sets no-new-privileges and breaks it).
  google-antigravity-ide-no-fhs = pkgs.callPackage ./pkgs/antigravity/package.nix {
    appType = "Antigravity IDE";
    useFHS = false;
  };
  google-antigravity-cli = pkgs.callPackage ./pkgs/antigravity/cli.nix { };

  # Terminal coding-agent CLI. See pkgs/oh-my-pi/default.nix header for
  # provenance (vendored prebuilt-binary release, same pattern as
  # google-antigravity-cli above).
  oh-my-pi = pkgs.callPackage ./pkgs/oh-my-pi { };

  # Command-line tool for downloading APK files from Google Play, F-Droid, and APKPure
  apkeep = pkgs.callPackage ./pkgs/apkeep { };

  # Native messaging host (binary + manifest) for kleinbem/chrome-open-in-app.
  chrome-open-in-app-host = pkgs.callPackage ./pkgs/chrome-open-in-app-host { };

  # Relay server, admin CLI, and pairing relay for the self-hosted Buzz workspace.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569154
  buzz-relay = pkgs.callPackage ./pkgs/buzz-relay/package.nix { };

  # Git credential helper producing NIP-98 authentication headers for Nostr git repos.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569173
  git-credential-nostr = pkgs.callPackage ./pkgs/git-credential-nostr/package.nix { };

  # NIP-GS git commit/tag signing program using Nostr secp256k1 keys.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569176
  git-sign-nostr = pkgs.callPackage ./pkgs/git-sign-nostr/package.nix { };

  # Model Context Protocol (MCP) server for Buzz developers and AI coding agents.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569182
  buzz-dev-mcp = pkgs.callPackage ./pkgs/buzz-dev-mcp/package.nix { };

  # Minimal, unbreakable ACP-compliant autonomous AI agent for Buzz workspace.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569247
  buzz-agent = pkgs.callPackage ./pkgs/buzz-agent/package.nix { };

  # Agent-first CLI for the Buzz relay and workspace.
  buzz-cli = pkgs.callPackage ./pkgs/buzz-cli/package.nix { };

  # Agent Control Protocol (ACP) bridge for the Buzz workspace.
  buzz-acp = pkgs.callPackage ./pkgs/buzz-acp/package.nix { };

  # Git prepare-commit-msg hook that adds AI agent attribution (block/aittributor).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  aittributor = pkgs.callPackage ./pkgs/aittributor/package.nix { };

  # Merges system, user and repo lefthook configs into one set of git hooks (block/lhm).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  lhm = pkgs.callPackage ./pkgs/lhm/package.nix { };

  # LLM code reviewer built on Goose (block/review; the attribute carries the
  # org because "review" alone says nothing). In nixpkgs form for a later PR.
  block-review = pkgs.callPackage ./pkgs/block-review/package.nix { };

  # MCP server + CLI that queue agents' expensive commands (block/agent-task-queue).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  agent-task-queue = pkgs.callPackage ./pkgs/agent-task-queue/package.nix { };

  # MCP server for GIMP 3 (tifyr/gimp3-mcp); nix-presets' mcp.nix also
  # installs the GIMP plugin from its sdist. Own package so nix-holds can
  # hold it while it needs mcp 1.x.
  gimp3-mcp = pkgs.callPackage ./pkgs/gimp3-mcp/package.nix { };

  # CLI for ANCHORS, requirements-driven development for agents (block/anchorsmd).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  anchors = pkgs.callPackage ./pkgs/anchors/package.nix { };

  # Manage AI rules, commands and skills across coding agents (block/ai-rules).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  ai-rules = pkgs.callPackage ./pkgs/ai-rules/package.nix { };

  # Dumps Claude Code and goose session histories as one JSON format (block/braindump).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  braindump = pkgs.callPackage ./pkgs/braindump/package.nix { };

  # LLM-based security scanner writing SARIF (block/codecrucible).
  # In nixpkgs form (by-name package.nix) for a later nixpkgs PR.
  codecrucible = pkgs.callPackage ./pkgs/codecrucible/package.nix { };

  # AI-driven UI testing for Android, iOS and web (block/trailblaze; uber JAR +
  # launcher as upstream ships it). In nixpkgs form for a later nixpkgs PR.
  trailblaze = pkgs.callPackage ./pkgs/trailblaze/package.nix { };

  # some-qt5-package = pkgs.libsForQt5.callPackage ./pkgs/some-qt5-package { };
  # ...
}
