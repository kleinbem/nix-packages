# nixpkgs' buzz-app, built from a block/buzz-app commit instead of a release.
#
# Everything comes from the nixpkgs checkout; this only swaps the source and
# the two dependency hashes (Cargo, pnpm), which run.sh learns first (an empty
# hash makes Nix print it).
{
  nixpkgs,
  rev,
  match ? false,
  cargoHash ? "",
  pnpmHash ? "",
}:

let
  src =
    builtins.fetchTree {
      type = "github";
      owner = "block";
      repo = "buzz-app";
      inherit rev;
    }
    // {
      name = "source";
    };

  overlay = final: prev: {
    buzz-app = prev.buzz-app.overrideAttrs (
      old:
      let
        cargoPatches = if match then [ ] else old.cargoPatches;
      in
      {
        inherit src;
        # Drop the 0.80 bump patch once buzz-app main pins a matching MeshLLM.
        patches = if match then final.lib.subtractLists old.cargoPatches old.patches else old.patches;
        # main may already drop /usr/bin/printenv (block/buzz-app#2417).
        postPatch =
          builtins.replaceStrings
            [ "--replace-fail /usr/bin/printenv" ]
            [ "--replace-quiet /usr/bin/printenv" ]
            old.postPatch;
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          name = "buzz-app-vendor";
          inherit src;
          patches = cargoPatches;
          hash = cargoHash;
        };
        pnpmDeps = old.pnpmDeps.overrideAttrs {
          inherit src;
          outputHash = pnpmHash;
          outputHashAlgo = "sha256";
        };
      }
    );
  };

  pkgs = import nixpkgs { overlays = [ overlay ]; };
in
{
  inherit (pkgs) buzz-app;
  # For run.sh, to learn the hashes.
  inherit (pkgs.buzz-app) cargoDeps pnpmDeps;
}
