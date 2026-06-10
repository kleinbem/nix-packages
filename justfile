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
    @echo "📋 Available packages:"
    @nix flake show . --json 2>/dev/null | jq -r '.packages."x86_64-linux" | keys[]' 2>/dev/null || nix flake show .

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
