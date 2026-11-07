#!/usr/bin/env bash
# Does a buzz-app commit pin a MeshLLM that matches nixpkgs' mesh-llm? Shared
# compute splits models only between nodes of the same skippy stage protocol
# generation, and the app loads only a runtime with its skippy ABI.
#
#   BUZZ_APP_REV=<commit> NIXPKGS_REPO=kleinbem/nixpkgs NIXPKGS_REF=<branch> canary/buzz-app/mesh-match.sh
#
# Prints key=value lines (app_*, nixpkgs_*, match=true|false) for $GITHUB_OUTPUT.
set -euo pipefail

raw() { curl -fsSL "https://raw.githubusercontent.com/$1/$2/$3"; }

# The first of the paths that exists at the MeshLLM commit; skippy moved into
# skippy/ on main.
mesh_file() {
  local rev=$1 path
  shift
  for path in "$@"; do
    raw Mesh-LLM/mesh-llm "$rev" "$path" 2>/dev/null && return
  done
  echo "none of $* at MeshLLM $rev" >&2
  return 1
}

# "<generation> <abi>" of a MeshLLM commit.
versions() {
  local rev=$1 generation abi
  generation="$(mesh_file "$rev" skippy/crates/skippy-protocol/src/validation.rs crates/skippy-protocol/src/validation.rs |
    sed -n 's/^pub const STAGE_PROTOCOL_GENERATION: u32 = \([0-9]*\);/\1/p')"
  abi="$(mesh_file "$rev" skippy/crates/skippy-ffi/src/lib.rs crates/skippy-ffi/src/lib.rs |
    sed -n 's/^pub const ABI_VERSION_[A-Z]*: u32 = \([0-9]*\);/\1/p' | paste -sd .)"
  [[ -n $generation && -n $abi ]] || {
    echo "no stage generation or skippy ABI at MeshLLM $rev" >&2
    return 1
  }
  echo "$generation $abi"
}

app_rev="$(raw block/buzz-app "${BUZZ_APP_REV:?}" src/bundled/mesh-compute/compute/Cargo.toml |
  sed -n 's/^mesh-llm-sdk = .*rev = "\([0-9a-f]\{40\}\)".*/\1/p')"
[[ -n $app_rev ]] || {
  echo "buzz-app $BUZZ_APP_REV pins no mesh-llm-sdk revision" >&2
  exit 1
}

# nixpkgs pins a commit (rev) until a release, then the tag of its version.
runtime="$(raw "${NIXPKGS_REPO:?}" "${NIXPKGS_REF:?}" pkgs/by-name/sk/skippy-native-runtime/package.nix |
  sed -n '/release ? {/,/};/p')"
nixpkgs_rev="$(sed -n 's/^ *rev = "\([0-9a-f]\{40\}\)";/\1/p' <<<"$runtime")"
if [[ -z $nixpkgs_rev ]]; then
  nixpkgs_rev="v$(sed -n 's/^ *version = "\([^"]*\)";/\1/p' <<<"$runtime")"
fi

read -r app_generation app_abi < <(versions "$app_rev")
read -r nixpkgs_generation nixpkgs_abi < <(versions "$nixpkgs_rev")
match=false
[[ $app_generation == "$nixpkgs_generation" && $app_abi == "$nixpkgs_abi" ]] && match=true

cat <<EOF
app_mesh_rev=$app_rev
app_generation=$app_generation
app_abi=$app_abi
nixpkgs_mesh_rev=$nixpkgs_rev
nixpkgs_generation=$nixpkgs_generation
nixpkgs_abi=$nixpkgs_abi
match=$match
EOF
