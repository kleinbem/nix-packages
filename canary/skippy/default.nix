# nixpkgs' skippy packages built from a Mesh-LLM/skippy commit instead of a
# release, so packaging breakage shows up before the split reaches nixpkgs.
{
  nixpkgs,
  rev,
  # The llama.cpp release number (its bNNNNN tag), which the library reports.
  llamaCppBuild,
  config ? { },
}:

let
  github =
    owner: repo: rev:
    builtins.fetchTree {
      type = "github";
      inherit owner repo rev;
    }
    // {
      name = "source";
    };

  skippySrc = github "Mesh-LLM" "skippy" rev;

  pkgs = import nixpkgs {
    overlays = [
      (import ./overlay.nix { inherit skippySrc llamaCppBuild; })
    ];
    inherit config;
  };
in
{
  inherit (pkgs) skippy skippy-tools;
  native-runtime = pkgs.skippy-native-runtime;
  serve = pkgs.skippy.tests.serve;
  runtime-rocm = pkgs.skippy-native-runtime.override {
    rocmSupport = true;
    rocmGpuTargets = [ "gfx1100" ];
  };
  runtime-cuda = pkgs.skippy-native-runtime.override { cudaSupport = true; };
}
