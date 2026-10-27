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
  # nixpkgs config, e.g. CUDA for the GPU runner:
  # { allowUnfree = true; cudaSupport = true; cudaCapabilities = [ "8.7" ]; }
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

  # The runtime's attribute: skippy-native-runtime since the prep branch for
  # 0.79 renamed it after upstream, mesh-llm-native-runtime before.
  runtimeAttr =
    pkgs': if pkgs' ? skippy-native-runtime then "skippy-native-runtime" else "mesh-llm-native-runtime";

  overlay = final: prev: {
    ${runtimeAttr prev} = prev.${runtimeAttr prev}.overrideAttrs (old: {
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

  pkgs = import nixpkgs {
    overlays = [ overlay ];
    inherit config;
  };

  # The 1 MB model of nixpkgs' NixOS test.
  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggml-org/models-moved/resolve/499bc8821c6b12b4e53c5bffcb21ec206f212d81/tinyllamas/stories260K.gguf";
    hash = "sha256-Jwy6G9UQn0LQM1D2BAYCRWBGTbFzwOOH2R8EJtO9JW0=";
  };

  # The hosts a program tries to reach while it starts serving the model, through
  # a local proxy that refuses every connection (the sandbox has no network
  # anyway). Fails when they differ from `expected`: a new request, or one that
  # went away.
  startupHosts =
    {
      name,
      package,
      # Starts serving in the background with the API on 127.0.0.1:19337.
      serve,
      expected,
    }:
    pkgs.runCommand "${name}-startup-hosts"
      {
        nativeBuildInputs = [
          package
          pkgs.python3
          pkgs.curl
          pkgs.cacert
        ];
        meta.platforms = pkgs.lib.platforms.linux;
      }
      ''
        export HOME=$TMPDIR/home XDG_CACHE_HOME=$TMPDIR/cache XDG_CONFIG_HOME=$TMPDIR/config
        export XDG_STATE_HOME=$TMPDIR/state
        mkdir -p $HOME/.mesh-llm

        python3 -I ${./proxy.py} 18080 --refuse > proxy.log 2>&1 &
        proxy=$!
        export HTTPS_PROXY=http://127.0.0.1:18080 HTTP_PROXY=http://127.0.0.1:18080
        export ALL_PROXY=$HTTPS_PROXY NO_PROXY=127.0.0.1,localhost
        ${serve} > serve.log 2>&1 &
        pid=$!
        for _ in $(seq 360); do
          curl -fsS --noproxy '*' http://127.0.0.1:19337/v1/models 2>/dev/null | grep -q '"id"' && break
          kill -0 $pid || { cat serve.log; echo "${name} exited before serving" >&2; exit 1; }
          sleep 0.5
        done
        curl -fsS --noproxy '*' http://127.0.0.1:19337/v1/models | grep -q '"id"' \
          || { cat serve.log; echo "${name} did not serve the model" >&2; exit 1; }
        # Requests made after readiness count too.
        sleep 20
        kill -INT $pid; timeout 30 tail --pid=$pid -f /dev/null || true
        kill $proxy

        # Hosts only; the iroh relay names are the mesh's own and may change.
        awk '{ print $3 }' proxy.log | sed -E 's|^https?://||; s|[:/].*||; s|.*\.iroh\.link\.?$|<iroh relays>|' \
          | LC_ALL=C sort -u > $out
        if ! diff -u ${expected} $out; then
          echo "the hosts ${name} contacts at startup changed (- expected, + now)" >&2
          exit 1
        fi
      '';
  runtimeTests =
    if (pkgs.skippy.tests or { }) ? runtime-rocm then pkgs.skippy.tests else pkgs.mesh-llm.tests;
in
{
  inherit (pkgs) mesh-llm;
  native-runtime = pkgs.${runtimeAttr pkgs};
  client-ready = pkgs.mesh-llm.tests.client-ready;
  nixos = pkgs.nixosTests.mesh-llm;
  # Build-only: the GPU runtimes need no GPU to build (runtime-cuda needs allowUnfree).
  # Their tests moved from mesh-llm to skippy when the packages were split.
  inherit (runtimeTests) runtime-rocm;
  runtime-cuda = runtimeTests.runtime-cuda or null;

  # `mesh-llm goose` against nixpkgs' Goose: mesh-llm writes Goose's custom
  # provider and MCP extension, then starts `goose session`; a shim turns that
  # into one non-interactive turn. Catches a change in either side's formats.
  goose =
    pkgs.runCommand "mesh-llm-goose"
      {
        nativeBuildInputs = [
          pkgs.mesh-llm
          pkgs.curl
          pkgs.cacert
          pkgs.jq
        ];
        meta.platforms = pkgs.lib.platforms.linux;
      }
      ''
        export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/home/.config XDG_CACHE_HOME=$TMPDIR/cache
        # A short answer: the 1 MB model would otherwise write until the output limit.
        export XDG_STATE_HOME=$TMPDIR/state GOOSE_DISABLE_KEYRING=1 GOOSE_MAX_TOKENS=32
        mkdir -p $HOME/.mesh-llm shim
        printf 'version = 1\n\n[[models]]\nmodel = "%s"\nctx_size = 8192\n' ${model} > $HOME/.mesh-llm/config.toml
        cat > shim/goose <<SHIM
        #!${pkgs.runtimeShell}
        [ "\$1" = session ] && shift
        exec ${pkgs.lib.getExe pkgs.goose-cli} run --no-session --no-profile --max-turns 1 --text "Once upon a time" "\$@"
        SHIM
        chmod +x shim/goose

        mesh-llm serve --log-format json --port 19337 --bind-port 17842 > serve.log 2>&1 &
        pid=$!
        for _ in $(seq 360); do
          curl -fsS http://127.0.0.1:19337/v1/models 2>/dev/null | grep -q '"id"' && break
          kill -0 $pid || { cat serve.log; echo "mesh-llm exited before serving" >&2; exit 1; }
          sleep 0.5
        done
        PATH=$PWD/shim:$PATH timeout 600 mesh-llm goose --port 19337 > goose.log 2>&1 \
          || { cat goose.log; echo "mesh-llm goose failed" >&2; exit 1; }
        kill -INT $pid; timeout 30 tail --pid=$pid -f /dev/null || true

        provider=$HOME/.config/goose/custom_providers/mesh.json
        jq -e '.engine == "openai" and .base_url == "http://localhost:19337"' $provider > /dev/null \
          || { cat $provider; echo "unexpected Goose provider" >&2; exit 1; }
        grep -q 'type: streamable_http' $HOME/.config/goose/config.yaml \
          || { cat $HOME/.config/goose/config.yaml; echo "no MCP extension in Goose's config" >&2; exit 1; }
        grep -q 'route=chat_completions' serve.log \
          || { tail -40 serve.log; echo "Goose sent no chat request to mesh-llm" >&2; exit 1; }
        tail -c 2000 goose.log > $out
      '';

  network = startupHosts {
    name = "mesh-llm";
    package = pkgs.mesh-llm;
    serve = ''
      printf 'version = 1\n\n[[models]]\nmodel = "%s"\n' ${model} > $HOME/.mesh-llm/config.toml
      mesh-llm serve --log-format json --port 19337 --console 13131 --bind-port 17842'';
    expected = ./expected-hosts.txt;
  };
}
// pkgs.lib.optionalAttrs (pkgs ? skippy) {
  # Skippy, released with MeshLLM (our nixpkgs PR has it before 0.79).
  inherit (pkgs) skippy;
  network-skippy = startupHosts {
    name = "skippy";
    package = pkgs.skippy;
    serve = "skippy serve --model ${model} --bind-addr 127.0.0.1:19337";
    expected = ./expected-hosts-skippy.txt;
  };
}
