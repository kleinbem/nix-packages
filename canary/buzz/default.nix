# nixpkgs' Buzz packages, built from a Buzz commit instead of a release.
#
# Everything comes from the nixpkgs checkout; this only swaps the source. The
# packages take it from buzz-cli, so overriding buzz-cli's src moves them all.
# The dependency hashes (Cargo for the workspace and the desktop, pnpm for the
# desktop and the relay web bundle) change with the commit: run.sh learns them
# first (an empty hash makes Nix print it). importCargoLock can't be used: the
# lockfile has sqlx-core 0.9.0 from both crates.io and git.
{
  nixpkgs,
  rev,
  workspaceCargoHash ? "",
  desktopCargoHash ? "",
  desktopPnpmHash ? "",
  relayWebPnpmHash ? "",
}:

let
  src =
    builtins.fetchTree {
      type = "github";
      owner = "block";
      repo = "buzz";
      inherit rev;
    }
    // {
      name = "source";
    };

  # One vendor directory per lockfile, shared by every package that uses it.
  cargoDeps =
    final: name: hash: extra:
    final.rustPlatform.fetchCargoVendor (
      {
        inherit name src hash;
      }
      // extra
    );

  pnpmHash =
    hash: deps:
    deps.overrideAttrs {
      outputHash = hash;
      outputHashAlgo = "sha256";
    };

  # The packages built from the workspace's Cargo.lock.
  workspacePackages = [
    "buzz-cli"
    "buzz-agent"
    "buzz-dev-mcp"
    "git-credential-nostr"
    "git-sign-nostr"
    "buzz-acp"
    "buzz-backend-kubernetes"
    "buzz-relay"
  ];

  overlay =
    final: prev:
    prev.lib.genAttrs workspacePackages (
      name:
      prev.${name}.overrideAttrs (
        old:
        {
          cargoDeps = cargoDeps final "buzz-workspace-vendor" workspaceCargoHash { };
        }
        // prev.lib.optionalAttrs (name == "buzz-cli") { inherit src; }
        // prev.lib.optionalAttrs (name == "buzz-relay") {
          passthru = old.passthru // {
            web = old.passthru.web.overrideAttrs (web: {
              pnpmDeps = pnpmHash relayWebPnpmHash web.pnpmDeps;
            });
          };
        }
      )
    )
    // {
      buzz-desktop = prev.buzz-desktop.overrideAttrs (old: {
        cargoDeps = cargoDeps final "buzz-desktop-vendor" desktopCargoHash {
          cargoRoot = "desktop/src-tauri";
        };
        pnpmDeps = pnpmHash desktopPnpmHash old.pnpmDeps;
      });
    };

  pkgs = import nixpkgs { overlays = [ overlay ]; };
in
{
  # For run.sh, to learn the hashes.
  workspaceCargoDeps = pkgs.buzz-cli.cargoDeps;
  desktopCargoDeps = pkgs.buzz-desktop.cargoDeps;

  inherit (pkgs)
    buzz-cli
    buzz-agent
    buzz-dev-mcp
    git-credential-nostr
    git-sign-nostr
    buzz-acp
    buzz-backend-kubernetes
    buzz-relay
    buzz-desktop
    ;
  # Every package's smoke tests (passthru.tests), in one attribute.
  tests = pkgs.linkFarm "buzz-tests" (
    pkgs.lib.concatMap (
      name:
      pkgs.lib.mapAttrsToList (test: drv: {
        name = "${name}-${test}";
        path = drv;
      }) (removeAttrs (pkgs.${name}.passthru.tests or { }) [ "nixos" ])
    ) workspacePackages
  );
  nixos = pkgs.nixosTests.buzz-relay;
}
