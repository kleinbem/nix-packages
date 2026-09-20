# nix-packages

Custom package derivations for the kleinbem fleet, structured as a
[NUR](https://github.com/nix-community/NUR)-style repo: `default.nix`
exposes an attrset of packages, `overlay.nix` exposes the same set as a
nixpkgs overlay.

## Packages

| Attribute | What it is |
|---|---|
| `langfuse` | Self-hosted LLM observability service. |
| `ricoh-driver` | Printer driver package. |
| `kleinbem-site` | Build of the `kleinbem-site` repo (kleinbem.dev). |
| `kleinbem-auth` | Build of the `kleinbem-auth` repo (visitor login service). |
| `google-antigravity`, `google-antigravity-ide`, `google-antigravity-ide-no-fhs`, `google-antigravity-cli` | Google Antigravity IDE/CLI, vendored from an audited derivation. Namespaced under `google-antigravity*` to avoid clobbering nixpkgs' own `antigravity` attr. |
| `oh-my-pi` | Terminal coding-agent CLI, vendored prebuilt-binary release. |
| `buzz-desktop` | Desktop client for the self-hosted Buzz relay (see `nix-presets/containers/buzz.nix`). |

`modules/nixos/langfuse.nix` ships a NixOS module alongside the `langfuse`
package.

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
