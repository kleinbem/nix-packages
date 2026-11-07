# nix-packages Justfile
#
# Custom packages (NUR-style) overlay. Recipes that maintain or extend the
# package set live here. Cross-repo workflows stay in the meta-workspace.

[group("Main")]
default:
    @just --list

# --- Validation ---

[group("Linter")]
check:
    @echo "📦 Verifying nix-packages flake..."
    @nix flake check . --impure

[group("Linter")]
fmt:
    @nix fmt

# --- Build helpers ---

[group("Build")]
build pkg:
    @echo "🔨 Building {{pkg}}..."
    @nix build .#{{pkg}}

[group("Build")]
list:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📋 Available packages:"
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"
    nix eval --json ".#packages.$system" --apply builtins.attrNames | jq -r '.[]'

# --- Upstream version bumps ---
# Each updater queries the upstream and rewrites versions.json (or equivalent).
# Review the diff with `git diff` and commit afterwards.

[group("Updates")]
update-antigravity:
    @./scripts/update-antigravity.sh
    @echo "✅ versions.json updated — review 'git diff' and commit."

[group("Updates")]
update-langfuse:
    @./scripts/update-langfuse.sh
    @echo "✅ langfuse pinned — review 'git diff' and commit."

[group("Updates")]
update-buzz-source:
    @./scripts/update-buzz-source.sh
    @echo "✅ pkgs/buzz/source.json updated — review 'git diff' and commit."

# Packages whose updateScript is nix-update-script (workflow update-packages.yaml).
[group("Updates")]
update-package pkg:
    @./scripts/update-packages.sh update {{pkg}}
