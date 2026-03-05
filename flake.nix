{
  description = "My personal NUR repository";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      flake = {
        overlays.default = import ./overlay.nix;
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
          legacyPkgs = import ./default.nix { pkgs = pkgsUnfree; };
        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };

          checks.pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
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

          packages = lib.filterAttrs (_: v: lib.isDerivation v) legacyPkgs;
        };
    };
}
