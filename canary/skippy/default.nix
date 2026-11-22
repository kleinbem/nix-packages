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
    skippy-native-runtime = prev.skippy-native-runtime.overrideAttrs (
      old:
      let
        inherit (old.passthru) backend;
        gpuBackendLib =
          {
            cuda = "libggml-cuda.so";
            rocm = "libggml-hip.so";
          }
          .${backend} or null;
      in
      {
        version =
          (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
        src = github "ggml-org" "llama.cpp" (
          final.lib.trim (builtins.readFile "${skippySrc}/llama_cpp/upstream.txt")
        );
        postPatch = ''
          llamaDir=${skippySrc}/llama_cpp
          patchDir=$llamaDir/patches
          shopt -s nullglob
          queue=("$patchDir"/*.patch)
          shopt -u nullglob
          for set in model_support generated; do
            if [ -f "$patchDir/$set/series" ]; then
              while IFS= read -r p || [ -n "$p" ]; do
                p=''${p%$'\r'}
                [[ -z "$p" || "$p" == \#* ]] && continue
                queue+=("$patchDir/$set/$p")
              done < "$patchDir/$set/series"
            fi
          done
          if (( ''${#queue[@]} > 0 )); then
            git init -q
            git add -A
            gitArgs=(-c user.name=nixbld -c user.email=nixbld@localhost -c core.hooksPath=/dev/null -c gc.auto=0)
            git "''${gitArgs[@]}" commit -q --no-gpg-sign -m base
            git "''${gitArgs[@]}" am -q --3way --no-gpg-sign "''${queue[@]}"
            rm -rf .git
          fi

          appendToVar cmakeFlags "-DLLAMA_BUILD_COMMIT=$(head -c 7 $llamaDir/upstream.txt)"
        '';
        preFixup = ''
          packageNativeRuntime() {
            cp -r ${skippySrc} skippy && chmod -R u+w skippy
            ${final.lib.optionalString (gpuBackendLib != null) ''
              NIX_LDFLAGS+=" -rpath $(patchelf --print-rpath $out/lib/ggml-backends/${gpuBackendLib})"
            ''}
            ${final.lib.optionalString (backend == "cuda") ''
              export CUDA_LIBRARY_PATH=${final.cudaPackages.cuda_cudart}/lib
              export SKIPPY_CUDA_LICENSE_FILE=${final.cudaPackages.cuda_cudart}/LICENSE
              export LLAMA_STAGE_CUDA_ARCHITECTURES="${final.cudaPackages.flags.cmakeCudaArchitecturesString}"
            ''}
            ${final.lib.optionalString (backend == "rocm") ''
              export HIPCC=${final.rocmPackages.clr}/bin/hipcc
              export LLAMA_STAGE_AMDGPU_TARGETS="${
                let
                  hipFlags = builtins.filter (final.lib.hasPrefix "-DCMAKE_HIP_ARCHITECTURES") (
                    old.cmakeFlags or [ ]
                  );
                in
                if hipFlags != [ ] then
                  final.lib.last (final.lib.splitString "=" (builtins.head hipFlags))
                else
                  final.lib.concatStringsSep ";" (
                    final.rocmPackages.clr.localGpuTargets or final.rocmPackages.clr.gpuTargets
                  )
              }"
            ''}
            export SKIPPY_NATIVE_RUNTIME_RANK=1000
            export LLAMA_WORKDIR=$NIX_BUILD_TOP/source
            mkdir -p core && cp -P $out/lib/lib*${final.stdenv.hostPlatform.extensions.sharedLibrary}* core/
            LLAMA_STAGE_BUILD_DIR=$PWD/core \
              bash skippy/scripts/package-native-runtime.sh --backend ${backend} \
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
      }
    );

    skippy = prev.skippy.overrideAttrs (old: {
      version =
        (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
      src = skippySrc;
      cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${skippySrc}/Cargo.lock"; };
      postInstall =
        builtins.replaceStrings
          [ "MESH_LLM_NATIVE_RUNTIME_BUNDLE_DIR" ]
          [ "SKIPPY_NATIVE_RUNTIME_BUNDLE_DIR" ]
          (old.postInstall or "");
    });

    skippy-tools = prev.skippy-tools.overrideAttrs (old: {
      version =
        (builtins.fromTOML (builtins.readFile "${skippySrc}/Cargo.toml")).workspace.package.version;
      src = skippySrc;
      cargoDeps = final.rustPlatform.importCargoLock { lockFile = "${skippySrc}/Cargo.lock"; };
      postPatch = builtins.replaceStrings [ "skippy/crates/" ] [ "crates/" ] (old.postPatch or "");
      postInstall =
        builtins.replaceStrings
          [ "MESH_LLM_NATIVE_RUNTIME_BUNDLE_DIR" ]
          [ "SKIPPY_NATIVE_RUNTIME_BUNDLE_DIR" ]
          (old.postInstall or "");
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
