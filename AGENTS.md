# nix-packages

Custom package derivations for the fleet, structured as a
[NUR](https://github.com/nix-community/NUR)-style repo (`default.nix` +
`overlay.nix`).

## Layout

| Path | What lives here |
|---|---|
| `pkgs/` | One directory per package: `antigravity`, `buzz-desktop`, `kleinbem-auth`, `kleinbem-site`, `langfuse`, `oh-my-pi`, `ricoh-driver`. |
| `default.nix` | The NUR-style attrset (`pkgs.callPackage ./pkgs/<name> { }` per package) consumed by `nix-config` and other flakes. |
| `overlay.nix` | Same packages exposed as a nixpkgs overlay, for consumers who don't want the whole NUR namespace. |
| `modules/nixos/` | NixOS modules shipped alongside the packages (not just derivations). |
| `ci.nix` | CI build set. |
| `canary/` | Nightly canaries building nixpkgs packages against upstream main (`canary/mesh-llm`, workflow `canary-mesh-llm.yaml`), to catch packaging breakage before the next release. |
| `watch/upstream-prs/` | Weekly look at our open upstream PRs (`prs.txt`, workflow `watch-upstream-prs.yaml`): conflicts, merges, new reviews or CI runs go into one issue. |

## Conventions

- `kleinbem-site` and `kleinbem-auth` packages here are how those app
  repos' builds reach `nix-config`/`container-factory` — a version bump
  there means pinning a new revision here (see `kleinbem-site`'s own docs
  for the 4-repo update chain: site → nix-packages pin+hashes →
  nix-config flake.lock → deploy).
- Add a new package as its own `pkgs/<name>/` directory + one line in
  `default.nix`, following the existing packages' structure — don't
  inline a derivation directly in `default.nix`.
