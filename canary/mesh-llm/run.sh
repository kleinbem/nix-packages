#!/usr/bin/env bash
# Builds nixpkgs' mesh-llm packages against a MeshLLM commit (default: main),
# so packaging breakage shows up before the next release reaches nixpkgs.
#
#   NIXPKGS=~/nixpkgs canary/mesh-llm/run.sh [attr...]
#
# NIXPKGS: a nixpkgs checkout with the mesh-llm packages.
# MESH_LLM_REV: the MeshLLM commit to build (default: main).
# attrs: what to build (default: mesh-llm-native-runtime mesh-llm client-ready network nixos).
set -euo pipefail

nixpkgs="$(realpath "${NIXPKGS:?set NIXPKGS to a nixpkgs checkout}")"
here="$(dirname "$(realpath "$0")")"
repo=https://github.com/Mesh-LLM/mesh-llm
rev="${MESH_LLM_REV:-$(git ls-remote "$repo" refs/heads/main | cut -f1)}"
echo "MeshLLM $rev"

# llama.cpp reports its release number (the bNNNNN tag), which the source
# tarball doesn't carry. MeshLLM pins a commit, so find the tag pointing at it.
llama_rev=""
for pin in skippy/llama_cpp/upstream.txt third_party/llama.cpp/upstream.txt; do
  llama_rev="$(curl -fsSL "https://raw.githubusercontent.com/Mesh-LLM/mesh-llm/$rev/$pin" | tr -d '[:space:]')" && break
done
llama_build="$(git ls-remote --tags https://github.com/ggml-org/llama.cpp 'refs/tags/b*' |
  awk -v rev="$llama_rev" '$1 == rev && !found { sub("refs/tags/b", "", $2); print $2; found = 1 }')"
if [[ -z $llama_build ]]; then
  echo "warning: no llama.cpp release tag points at ${llama_rev:-the pin}; reporting build 0" >&2
  llama_build=0
fi

args=(--arg nixpkgs "$nixpkgs" --argstr rev "$rev" --argstr llamaCppBuild "$llama_build")

# The pnpm dependencies have no lockfile-derived hash: build them once with an
# empty one and take the hash Nix reports.
pnpm_hash="$(
  (nix-build "$here" "${args[@]}" -A mesh-llm.pnpmDeps --no-out-link 2>&1 || true) |
    sed -n 's/^ *got: *//p' | tail -n 1
)"
if [[ -z $pnpm_hash ]]; then
  echo "could not determine the pnpm dependency hash" >&2
  nix-build "$here" "${args[@]}" -A mesh-llm.pnpmDeps --no-out-link
  exit 1
fi

if (($# == 0)); then
  set -- mesh-llm-native-runtime mesh-llm client-ready network nixos
fi
attrs=()
for attr in "$@"; do
  attrs+=(-A "$attr")
done
nix-build "$here" "${args[@]}" --argstr pnpmHash "$pnpm_hash" "${attrs[@]}" --no-out-link --keep-going
