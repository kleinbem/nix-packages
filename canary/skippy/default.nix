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

  overlay = final: prev: {
    skippy-native-runtime = prev.skippy-native-runtime.overrideAttrs (old: {
      version =
        (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
      src = github "ggml-org" "llama.cpp" (
        final.lib.trim (builtins.readFile "${skippySrc}/llama_cpp/upstream.txt")
      );
      postPatch = ''
        llamaDir=${skippySrc}/llama_cpp
        patchDir=$llamaDir/patches
        queue=("$patchDir"/*.patch)
        for set in model_support generated; do
          if [ -f "$patchDir/$set/series" ]; then
            while IFS= read -r p || [ -n "$p" ]; do queue+=("$patchDir/$set/''${p%$'\r'}"); done < "$patchDir/$set/series"
          fi
        done
        git init -q
        git add -A
        gitArgs=(-c user.name=nixbld -c user.email=nixbld@localhost -c core.hooksPath=/dev/null -c gc.auto=0)
        git "''${gitArgs[@]}" commit -q --no-gpg-sign -m base
        git "''${gitArgs[@]}" am -q --3way --no-gpg-sign "''${queue[@]}"
        rm -rf .git

        appendToVar cmakeFlags "-DLLAMA_BUILD_COMMIT=$(head -c 7 $llamaDir/upstream.txt)"
      '';
      preFixup = ''
        packageNativeRuntime() {
          cp -r ${skippySrc} skippy && chmod -R u+w skippy
          export SKIPPY_NATIVE_RUNTIME_RANK=1000
          export LLAMA_WORKDIR=$NIX_BUILD_TOP/source
          mkdir -p core && cp -P $out/lib/lib*${final.stdenv.hostPlatform.extensions.sharedLibrary}* core/
          LLAMA_STAGE_BUILD_DIR=$PWD/core \
            bash skippy/scripts/package-native-runtime.sh --backend ${old.passthru.backend} \
              --keep-runpath --no-model-package-tool --out $out/share/mesh-llm/runtimes \
              --id-suffix nixpkgs
          rm -f $out/share/mesh-llm/runtimes/*.tar.gz*
        }
        postFixupHooks+=(packageNativeRuntime)
      '';
      passthru = old.passthru // {
        inherit llamaCppBuild skippySrc;
        automation = null;
      };
    });

    skippy = prev.skippy.overrideAttrs (old: {
      version =
        (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
      src = skippySrc;
      cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${skippySrc}/Cargo.lock"; };
      postInstall =
        builtins.replaceStrings
          [ "MESH_LLM_NATIVE_RUNTIME_BUNDLE_DIR" ]
          [ "SKIPPY_NATIVE_RUNTIME_BUNDLE_DIR" ]
          old.postInstall;
    });

    skippy-tools = prev.skippy-tools.overrideAttrs (old: {
      version =
        (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
      src = skippySrc;
      cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${skippySrc}/Cargo.lock"; };
      postPatch =
        builtins.replaceStrings
          [ "skippy/crates/skippy-quantize/Cargo.toml" ]
          [ "crates/skippy-quantize/Cargo.toml" ]
          old.postPatch;
      postInstall =
        builtins.replaceStrings
          [ "MESH_LLM_NATIVE_RUNTIME_BUNDLE_DIR" ]
          [ "SKIPPY_NATIVE_RUNTIME_BUNDLE_DIR" ]
          old.postInstall;
    });
  };

  pkgs = import nixpkgs {
    overlays = [ overlay ];
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
