# A flake input's source at the commit in flake.lock, for imports without the
# flake (overlay.nix, nix-detour-fleet).
name:
let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  locked = lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
in
builtins.fetchTarball {
  url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.tar.gz";
  sha256 = locked.narHash;
}
