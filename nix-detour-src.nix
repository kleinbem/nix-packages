# nix-detour at the commit in flake.lock, for imports without the flake
# (overlay.nix, nix-detour-fleet).
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  locked = lock.nodes.${lock.nodes.root.inputs.nix-detour}.locked;
in
builtins.fetchTarball {
  url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
  sha256 = locked.narHash;
}
