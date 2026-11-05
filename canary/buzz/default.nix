# nixpkgs' Buzz packages, built from a Buzz commit instead of a release.
# Only the source changes; the packages take it from buzz-cli, so overriding
# buzz-cli's src moves them all. run.sh learns the Cargo and relay-web pnpm
# hashes first (an empty hash makes Nix print it). Not importCargoLock: the
# lockfile has sqlx-core 0.9.0 from both crates.io and git, and it keys crates
# by name-version (NixOS/nixpkgs#183344).
{
  nixpkgs,
  rev,
  workspaceCargoHash ? "",
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
    );

  pkgs = import nixpkgs { overlays = [ overlay ]; };
  inherit (pkgs) lib;
  available = lib.meta.availableOn pkgs.stdenv.hostPlatform;
  availablePackages = builtins.filter (name: available pkgs.${name}) workspacePackages;
in
{
  # For run.sh, to skip what this platform can't build (buzz-relay is
  # Linux-only, and so is the NixOS test).
  unavailable =
    builtins.filter (name: !available pkgs.${name}) workspacePackages
    ++ lib.optional (!pkgs.stdenv.hostPlatform.isLinux) "nixos";

  # For run.sh, to learn the hashes.
  workspaceCargoDeps = pkgs.buzz-cli.cargoDeps;

  inherit (pkgs)
    buzz-cli
    buzz-agent
    buzz-dev-mcp
    git-credential-nostr
    git-sign-nostr
    buzz-acp
    buzz-backend-kubernetes
    buzz-relay
    ;
  # Every package's smoke tests (passthru.tests), in one attribute.
  tests = pkgs.linkFarm "buzz-tests" (
    lib.concatMap (
      name:
      lib.mapAttrsToList (test: drv: {
        name = "${name}-${test}";
        path = drv;
      }) (lib.filterAttrs (_: available) (removeAttrs (pkgs.${name}.passthru.tests or { }) [ "nixos" ]))
    ) availablePackages
  );
  nixos = pkgs.nixosTests.buzz-relay;
}
