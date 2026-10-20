# nix-packages

Custom package derivations for the kleinbem fleet, structured as a
[NUR](https://github.com/nix-community/NUR)-style repo: `default.nix`
exposes an attrset of packages, `overlay.nix` exposes the same set as a
nixpkgs overlay.

## Packages

Three groups. The first two are the Block AI landscape (goose, Buzz, Berd,
MeshLLM) that this repo stages for nixpkgs and runs in the fleet; the third
is everything else the fleet needs.

### Block

| Attribute | What it is |
|---|---|
| `buzz-relay`, `buzz-cli`, `buzz-acp`, `buzz-agent`, `buzz-dev-mcp`, `git-credential-nostr`, `git-sign-nostr` | The Buzz workspace's Rust crates, one pinned source (`pkgs/buzz/source.json`). Staged for NixOS/nixpkgs#570552 and #574877; `buzz-cli` is already in nixpkgs. |
| `buzz-desktop` | Desktop client for the self-hosted Buzz relay (see `nix-presets/containers/buzz.nix`), with its sidecars. Staged for NixOS/nixpkgs#571723. |
| `berd` | Block's desktop app for AI agents (Tauri + React) on the Goose ACP backend, with nixpkgs' `goose-cli` as the `goosed` sidecar. Not in nixpkgs yet; written in nixpkgs form. |
| `aittributor` | Git prepare-commit-msg hook that adds AI agent attribution (block/aittributor). Not in nixpkgs yet; written in nixpkgs form. |
| `lhm` | Merges system, user and repo lefthook configs into one set of git hooks (block/lhm). Not in nixpkgs yet; written in nixpkgs form. |

### MeshLLM

| Attribute | What it is |
|---|---|
| `mesh-llm`, `mesh-llm-cuda`, `mesh-llm-rocm`, `skippy`, `skippy-native-runtime`, `skippy-native-runtime-vulkan` | NixOS/nixpkgs#571722, built from the PR branch's own package files (flake input `nixpkgs-mesh`, see `pkgs/mesh-llm/default.nix`), not copies. `nixosModules.mesh-llm` is the PR's `services.mesh-llm`. Goes away once the PR is in the fleet's nixpkgs. |

### Everything else

| Attribute | What it is |
|---|---|
| `langfuse` | Self-hosted LLM observability service. |
| `ricoh-driver` | Printer driver package. |
| `kleinbem-site` | Build of the `kleinbem-site` repo (kleinbem.dev). |
| `kleinbem-auth` | Build of the `kleinbem-auth` repo (visitor login service). |
| `google-antigravity`, `google-antigravity-ide`, `google-antigravity-ide-no-fhs`, `google-antigravity-cli` | Google Antigravity IDE/CLI, vendored from an audited derivation. Namespaced under `google-antigravity*` to avoid clobbering nixpkgs' own `antigravity` attr. |
| `oh-my-pi` | Terminal coding-agent CLI, vendored prebuilt-binary release. |
| `apkeep` | Downloads APKs from Google Play, F-Droid and APKPure. |
| `chrome-open-in-app-host` | Native messaging host for `kleinbem/chrome-open-in-app`. |

`modules/nixos/` ships NixOS modules alongside the packages: `langfuse`,
`buzz-relay`, and `mesh-llm` (from the `nixpkgs-mesh` input).

## Rule for packages that are also ours in nixpkgs

What we maintain in nixpkgs is consumed from there, never copied here. While
a package only exists on a PR branch of `kleinbem/nixpkgs`, this repo
re-exports the branch's package files against its own nixpkgs (the
`nixpkgs-mesh` input is the first case). Real derivations live here only for
software nobody has in nixpkgs yet, or for a channel nixpkgs doesn't carry
(upstream `main` for the canaries).

## Usage

```nix
inputs.nix-packages.url = "github:kleinbem/nix-packages";
# ...
environment.systemPackages = [
  inputs.nix-packages.packages.${system}.oh-my-pi
];
# or, as an overlay:
nixpkgs.overlays = [ inputs.nix-packages.overlays.default ];
```

## Adding a package

Add a new `pkgs/<name>/` directory with its derivation, then one line in
`default.nix` calling it — see the existing packages for the pattern.
`kleinbem-site`/`kleinbem-auth` are how those app repos' builds reach
`nix-config`/`container-factory`; bumping their version is part of a
4-repo chain (site → nix-packages pin+hashes → nix-config flake.lock →
deploy) — see `kleinbem-site`'s own docs for details.
