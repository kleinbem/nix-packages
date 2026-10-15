# nixpkgs' mesh-llm packages, built from a MeshLLM commit instead of a release.
#
# Everything comes from the nixpkgs checkout; this only swaps the sources.
# Inputs pinned by a commit (MeshLLM, llama.cpp) or a lockfile (Cargo.lock)
# need no hash. The console's pnpm dependencies are the one exception, so
# run.sh learns their hash first (pnpmHash = "" makes Nix print it).
{
  nixpkgs,
  rev,
  # The llama.cpp release number (its bNNNNN tag), which the library reports.
  llamaCppBuild,
  pnpmHash ? "",
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

  meshLlmSrc = github "Mesh-LLM" "mesh-llm" rev;

  # The pin moved from third_party/llama.cpp to skippy/llama_cpp after 0.78.
  llamaPin =
    let
      pins = builtins.filter builtins.pathExists [
        "${meshLlmSrc}/skippy/llama_cpp/upstream.txt"
        "${meshLlmSrc}/third_party/llama.cpp/upstream.txt"
      ];
    in
    if pins == [ ] then throw "MeshLLM ${rev} has no llama.cpp upstream.txt" else builtins.head pins;

  overlay = final: prev: {
    mesh-llm-native-runtime = prev.mesh-llm-native-runtime.overrideAttrs (old: {
      # mesh-llm --version reports the workspace version, which versionCheckHook checks.
      version =
        (builtins.fromTOML (builtins.readFile "${meshLlmSrc}/Cargo.toml")).workspace.package.version;
      src = github "ggml-org" "llama.cpp" (final.lib.trim (builtins.readFile llamaPin));
      passthru =
        old.passthru
        // {
          inherit meshLlmSrc llamaCppBuild;
        }
        # Upstream's automation tool (newer packages): its cargo hash is pinned
        # to one release, so take its dependencies from the lockfile as well.
        // final.lib.optionalAttrs (old.passthru ? automation) {
          automation = old.passthru.automation.overrideAttrs {
            src = meshLlmSrc;
            cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${meshLlmSrc}/Cargo.lock"; };
          };
        };
    });

    mesh-llm = prev.mesh-llm.overrideAttrs (old: {
      cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${meshLlmSrc}/Cargo.lock"; };
      pnpmDeps = old.pnpmDeps.overrideAttrs {
        outputHash = pnpmHash;
        outputHashAlgo = "sha256";
      };
    });
  };

  pkgs = import nixpkgs { overlays = [ overlay ]; };
in
{
  inherit (pkgs) mesh-llm mesh-llm-native-runtime;
  client-ready = pkgs.mesh-llm.tests.client-ready;
  nixos = pkgs.nixosTests.mesh-llm;
}
