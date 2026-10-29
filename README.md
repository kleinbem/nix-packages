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
| `aittributor` | Git prepare-commit-msg hook that adds AI agent attribution (block/aittributor). Not in nixpkgs yet; written in nixpkgs form. |
| `lhm` | Merges system, user and repo lefthook configs into one set of git hooks (block/lhm). Not in nixpkgs yet; written in nixpkgs form. |
| `block-review` | LLM code reviewer for git changes, built on Goose (block/review; binary `review`). Not in nixpkgs yet; written in nixpkgs form. |
| `agent-task-queue` | MCP server + `tq` CLI that queue agents' expensive commands so they run one at a time (block/agent-task-queue). Not in nixpkgs yet; written in nixpkgs form. |
| `anchors` | CLI for ANCHORS, Block's requirements-driven development framework for AI agents (block/anchorsmd). Not in nixpkgs yet; written in nixpkgs form. |
| `ai-rules` | Manage AI rules, commands and skills across 11 coding agents from one source (block/ai-rules). Not in nixpkgs yet; written in nixpkgs form. |
| `braindump` | Dumps Claude Code and goose agent session histories as one JSON format (block/braindump). Not in nixpkgs yet; written in nixpkgs form. |
| `codecrucible` | LLM-based security analysis of git repositories with an audit pass and SARIF output (block/codecrucible). Not in nixpkgs yet; written in nixpkgs form. |
| `trailblaze` | AI-driven UI testing framework for Android, iOS and web (block/trailblaze; upstream's uber JAR + launcher). Not in nixpkgs yet; written in nixpkgs form. |

### From our open nixpkgs PRs

| Attribute | What it is |
|---|---|
| `mesh-llm`, `mesh-llm-cuda`, `mesh-llm-rocm`, `skippy`, `skippy-native-runtime`, `skippy-native-runtime-vulkan` | MeshLLM, NixOS/nixpkgs#571722. `nixosModules.mesh-llm` is the PR's `services.mesh-llm`. |
| `buzz-app` | The Buzz desktop app, NixOS/nixpkgs#577918. |
| `berd` | Berd, Block's desktop app for AI agents on goose, NixOS/nixpkgs#580616. |

### Everything else

| Attribute | What it is |
|---|---|
| `langfuse` | Self-hosted LLM observability service. |
| `ricoh-driver` | Printer driver package. |
| `kleinbem-site` | Build of the `kleinbem-site` repo (kleinbem.dev). |
| `google-antigravity`, `google-antigravity-ide`, `google-antigravity-ide-no-fhs`, `google-antigravity-cli` | Google Antigravity IDE/CLI, vendored from an audited derivation. Namespaced under `google-antigravity*` to avoid clobbering nixpkgs' own `antigravity` attr. |
| `oh-my-pi` | Terminal coding-agent CLI, vendored prebuilt-binary release. |
| `apkeep` | Downloads APKs from Google Play, F-Droid and APKPure. |
| `chrome-open-in-app-host` | Native messaging host for `kleinbem/chrome-open-in-app`. |

`modules/nixos/` ships NixOS modules alongside the packages: `langfuse`,
`buzz-relay`, and `mesh-llm` (from its nixpkgs PR).

## Rule for packages that are also ours in nixpkgs

What we maintain in nixpkgs is consumed from there, never copied here. While
a package only exists on a nixpkgs PR, `nixpkgs-prs.json` pins the PR at one
commit and `lib/nixpkgs-prs.nix` builds the PR's own package files (and
modules) against this flake's nixpkgs. Real derivations live here only for
software nobody has in nixpkgs yet, or for a channel nixpkgs doesn't carry
(upstream `main` for the canaries).

The lifecycle of an entry:

1. **Add:** a new entry in `nixpkgs-prs.json` (PR number, repository, the
   attributes, any modules), by hand, then pin it.
2. **Pin:** run the *Pin nixpkgs PR* workflow with the entry and a commit
   whose packages are green on nixpkgs-review-gha. It opens a PR that
   auto-merges. The daily lock update never moves a pin, so nothing reaches
   the fleet unless it was pinned on purpose. nix-config's build-all builds
   the pinned packages with the fleet's nixpkgs before a host installs them.
3. **Remove:** the weekly *nixpkgs PRs merged* workflow opens a PR that
   removes an entry once nixpkgs has its packages in the same or a newer
   version. For an entry with modules it's a draft: switch nix-config to
   nixpkgs' module first.

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
`kleinbem-site` is how that app repo's build reaches
`nix-config`/`container-factory`; bumping its version is part of a
4-repo chain (site → nix-packages pin+hashes → nix-config flake.lock →
deploy) — see `kleinbem-site`'s own docs for details.
