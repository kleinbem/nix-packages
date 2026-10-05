# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

{
  pkgs ? import (builtins.getFlake "nixpkgs") { system = "x86_64-linux"; },
}:

{

  langfuse = pkgs.callPackage ./pkgs/langfuse { };
  ricoh-driver = pkgs.callPackage ./pkgs/ricoh-driver/default.nix { };

  # kleinbem.dev — see pkgs/kleinbem-site/default.nix header for the bump
  # procedure (pinned to a commit SHA, same pattern as langfuse above).
  kleinbem-site = pkgs.callPackage ./pkgs/kleinbem-site { };

  # better-auth login service for kleinbem.dev — pinned to a commit SHA, same
  # pattern as kleinbem-site. See pkgs/kleinbem-auth/default.nix header to bump.
  kleinbem-auth = pkgs.callPackage ./pkgs/kleinbem-auth { };

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

  # Relay server, admin CLI, and pairing relay for the self-hosted Buzz workspace.
  # Staged derivation matching upstream PR https://github.com/NixOS/nixpkgs/pull/569154
  buzz-relay = pkgs.callPackage ./pkgs/buzz-relay/package.nix { };

  # Desktop client for the self-hosted Buzz relay (nix-presets/containers/
  # buzz.nix). Built from source at the desktop-v* release tag, with its own
  # sidecars; mirrors upstream PR https://github.com/NixOS/nixpkgs/pull/569165
  buzz-desktop = pkgs.callPackage ./pkgs/buzz-desktop { };

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
  # some-qt5-package = pkgs.libsForQt5.callPackage ./pkgs/some-qt5-package { };
  # ...
}
