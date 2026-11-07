# You can use this file as a nixpkgs overlay. This is useful in the
# case where you don't want to add the whole NUR namespace to your
# configuration.

final: prev:
let
  inherit (prev) lib;
  isReserved = n: n == "lib" || n == "overlays" || n == "modules";
  # The packages of our open nixpkgs PRs come from nix-detour's overlay: it
  # builds them against the final package set and adds their Python packages
  # to every Python set, which an attrset of packages can't.
  prs = import "${import ./locked-input.nix "nix-detour"}/prs.nix" {
    inherit lib;
    prs = ./nixpkgs-prs.json;
  };
  prAttrs = lib.concatMap (entry: entry.attrs) (lib.attrValues prs.entries);
  nurAttrs = import ./default.nix { pkgs = prev; };
in
prs.overlay final prev // lib.filterAttrs (n: _: !isReserved n && !lib.elem n prAttrs) nurAttrs
