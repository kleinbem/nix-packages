#!/usr/bin/env bash
# Builds nixpkgs' skippy packages against a Mesh-LLM/skippy commit (default: main).
#
#   NIXPKGS=~/nixpkgs canary/skippy/run.sh [attr...]
#
# NIXPKGS: a nixpkgs checkout with the skippy packages.
# SKIPPY_REV: the Mesh-LLM/skippy commit to build (default: main).
# CANARY_NIXPKGS_CONFIG: a nixpkgs config expression (default: none), e.g. for CUDA.
# attrs: what to build (default: native-runtime skippy skippy-tools serve).
set -euo pipefail

nixpkgs="$(realpath "${NIXPKGS:?set NIXPKGS to a nixpkgs checkout}")"
here="$(dirname "$(realpath "$0")")"
repo=https://github.com/Mesh-LLM/skippy
rev="${SKIPPY_REV:-$(git ls-remote "$repo" refs/heads/main | cut -f1)}"
echo "Skippy $rev"

llama_rev="$(curl -fsSL "https://raw.githubusercontent.com/Mesh-LLM/skippy/$rev/llama_cpp/upstream.txt" | tr -d '[:space:]')"
llama_build="$(git ls-remote --tags https://github.com/ggml-org/llama.cpp 'refs/tags/b*' |
  awk -v rev="$llama_rev" '$1 == rev && !found { sub("refs/tags/b", "", $2); sub(/\^\{\}$/, "", $2); print $2; found = 1 }')"
if [[ -z $llama_build ]]; then
  echo "warning: no llama.cpp release tag points at ${llama_rev:-the pin}; reporting build 0" >&2
  llama_build=0
fi

args=(--arg nixpkgs "$nixpkgs" --argstr rev "$rev" --argstr llamaCppBuild "$llama_build")
if [[ -n ${CANARY_NIXPKGS_CONFIG:-} ]]; then
  args+=(--arg config "$CANARY_NIXPKGS_CONFIG")
fi

if (($# == 0)); then
  set -- native-runtime skippy skippy-tools serve
fi
attrs=()
for attr in "$@"; do
  attrs+=(-A "$attr")
done
nix-build "$here" "${args[@]}" "${attrs[@]}" --no-out-link --keep-going
