{
  description = "My personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    nix-devshells.url = "github:kleinbem/nix-devshells";
    nix-devshells.inputs.nixpkgs.follows = "nixpkgs";
    # Packages from our open nixpkgs PRs (nixpkgs-prs.json).
    nix-detour.url = "github:kleinbem-dev/nix-detour";
    nix-detour.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      prs = inputs.nix-detour.lib.mkPrs { prs = ./nixpkgs-prs.json; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      inherit systems;
      imports = [ ];

      flake = {
        overlays.default = import ./overlay.nix;
        # Plus the modules of our open nixpkgs PRs (services.mesh-llm), exactly
        # as in the PR; they need the overlay (or the packages) for their
        # packages. See nix-detour's mkPrs.
        nixosModules = {
          langfuse = import ./modules/nixos/langfuse.nix;
          buzz-relay = import ./modules/nixos/buzz-relay.nix;
        }
        // prs.nixosModules;

        # For nix-detour's pr-pin and pr-merged actions: the PR packages and
        # whether nixpkgs has caught up with them.
        nixpkgsPrs = inputs.nixpkgs.lib.genAttrs systems (
          system:
          prs.checks (
            import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            }
          )
        );
      };

      perSystem =
        {
          config,
          pkgs,
          lib,
          system,
          ...
        }:
        let
          pkgsUnfree = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          legacyPkgs = import ./default.nix {
            pkgs = pkgsUnfree;
            inherit (inputs) nix-detour;
          };
        in
        {
          formatter = inputs.nix-devshells.formatter.${system};

          checks.pre-commit-check = inputs.git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;
            };
          };

          devShells.default = pkgs.mkShell {
            shellHook = ''
              ${config.checks.pre-commit-check.shellHook}
              echo "📦 Packages Flake DevEnv"
            '';
            buildInputs = [
              pkgs.nixfmt
              pkgs.statix
              pkgs.deadnix
            ];
          };

          legacyPackages = legacyPkgs;

          packages = lib.filterAttrs (
            _: v: lib.isDerivation v && lib.meta.availableOn { inherit system; } v
          ) legacyPkgs;
        };
    };
}
