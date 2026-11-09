{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_24,
  pnpmConfigHook,
  fetchPnpmDeps,
  pnpm_12,
  rustPlatform,
  cargo,
  rustc,
  prisma-engines_6,
  prisma_6,
  go-migrate,
  python3,
  pkg-config,
  openssl,
  vips,
  makeWrapper,
  bash,
  coreutils,
  gnused,
  callPackage,
  # Build-time environment variables for Next.js frontend. A cloud region turns
  # on Langfuse Cloud behaviour (billing, dd-trace), so self-hosting leaves it null.
  nextPublicLangfuseCloudRegion ? null,
  nextTelemetryDisabled ? "1",
}:

let
  # Langfuse pins engines.node = 24.
  node = nodejs_24;
  # Only the ClickHouse driver, as web/Dockerfile builds it. nixpkgs' all-driver
  # build panics at start in gosnowflake's init ("failed to parse CA certificate").
  # Upstream fix in NixOS/nixpkgs#584660; drop once the fix reaches our nixpkgs input.
  migrate = go-migrate.overrideAttrs { tags = [ "clickhouse" ]; };
  pnpm = pnpm_12;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "langfuse";
  version = "4.75.0";

  src = fetchFromGitHub {
    owner = "langfuse";
    repo = "langfuse";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Y7OGygQwxIYwBLBUrl4vkhpvf5Fro6xgH8kuda1AhF4=";
  };

  nativeBuildInputs = [
    node
    pnpm
    pnpmConfigHook
    prisma-engines_6
    rustPlatform.cargoSetupHook
    cargo
    rustc
    python3 # Required for some node-gyp builds
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    openssl
    vips # Image processing
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    hash = "sha256-hPPWLWKWwnJbG78QFavkMbitEoM9YzMN2xD6KysKpsI=";
    # fetcherVersion 3 was rejected for pnpm 11 in nixpkgs ≥ 2026-06; 4 uses the
    # SQLite-dump store format (nixpkgs #522703) — hash computed against it.
    fetcherVersion = 4;
    prePnpmInstall = ''
      cp -r ${finalAttrs.src}/patches .
    '';
  };

  # Rust addon (napi-rs) the worker loads, built by turbo through `napi build`.
  # Its hash = stays after pnpmDeps': the updater sets them by position.
  cargoRoot = "packages/native";
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs)
      pname
      version
      src
      cargoRoot
      ;
    hash = "sha256-P6yuIy/sVJN0efu/Kr952QnfpE+QfnOkYPRg2TCI8wo=";
  };

  preConfigure = ''
    cp -r ${finalAttrs.src}/patches .
  '';

  # Required for Next.js build-time configuration and Prisma engines
  env = {
    NEXT_TELEMETRY_DISABLED = nextTelemetryDisabled;
    DOCKER_BUILD = "1";
    CI = "true";
    NODE_ENV = "production";

    # Point Prisma to the Nix-provided engines
    PRISMA_SCHEMA_ENGINE_BINARY = "${prisma-engines_6}/bin/schema-engine";
    PRISMA_QUERY_ENGINE_BINARY = "${prisma-engines_6}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${prisma-engines_6}/lib/libquery_engine.node";
    PRISMA_FMT_BINARY = "${prisma-engines_6}/bin/prisma-fmt";
    # pnpm re-checks node_modules before each run; the frozen install is authoritative.
    pnpm_config_verify_deps_before_run = "false";
  }
  // lib.optionalAttrs (nextPublicLangfuseCloudRegion != null) {
    NEXT_PUBLIC_LANGFUSE_CLOUD_REGION = nextPublicLangfuseCloudRegion;
  };

  buildPhase = ''
    runHook preBuild

    # Generate Prisma client
    pnpm run db:generate

    # Render the ClickHouse migrations up.sh applies at web start (as web/Dockerfile does).
    node ./packages/shared/clickhouse/scripts/prepare-migrations.mjs materialize ./packages/shared/clickhouse/migrations

    # Build web and worker with Turbo. Through pnpm: npx refuses to run since
    # Langfuse declares devEngines.packageManager = pnpm (EBADDEVENGINES).
    pnpm exec turbo run build --filter=web --filter=worker

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    lf=$out/lib/langfuse
    mkdir -p $lf/packages/shared/scripts

    # Next.js standalone output for the web app, laid out like web/Dockerfile's
    # runner so upstream's entrypoint.sh (migrations, then server) runs unchanged.
    cp -r web/.next/standalone/. $lf/
    cp -r web/.next/static $lf/web/.next/static
    cp -r web/public $lf/web/public
    install -m755 web/entrypoint.sh $lf/web/entrypoint.sh
    cp -r packages/shared/prisma packages/shared/clickhouse $lf/packages/shared/
    cp packages/shared/scripts/cleanup.sql $lf/packages/shared/scripts/

    # Worker: its own production node_modules with the workspace packages
    # (@langfuse/shared, the @langfuse/native addon) materialised. The deploy
    # reinstalls @prisma/client without the generated client, so that comes
    # from the build tree. no-link: mirrors upstream's worker/Dockerfile.
    pnpm --offline --filter worker deploy --prod $lf/worker
    # The client @langfuse/shared resolves; other @prisma/client copies may be stubs.
    prismaClientOf() {
      node -p "require('path').dirname(require.resolve('@prisma/client/package.json', { paths: [require('fs').realpathSync('$1')] }))"
    }
    builder_client=$(prismaClientOf packages/shared)
    deployed_client=$(prismaClientOf $lf/worker/node_modules/@langfuse/shared)
    rm -rf "$deployed_client" "$(dirname "$(dirname "$deployed_client")")/.prisma"
    cp -R "$builder_client" "$deployed_client"
    cp -R "$(dirname "$(dirname "$builder_client")")/.prisma" "$(dirname "$(dirname "$deployed_client")")/.prisma"

    chmod +x $lf/worker/entrypoint.sh

    # The entrypoints shell out to sh, sed and coreutils, which a systemd
    # unit's PATH lacks. Prisma loads the Nix engines, not downloaded ones.
    engineEnv=(
      --prefix PATH : ${
        lib.makeBinPath [
          node
          bash
          coreutils
          gnused
        ]
      }
      --set-default PRISMA_QUERY_ENGINE_LIBRARY ${prisma-engines_6}/lib/libquery_engine.node
      --set-default PRISMA_SCHEMA_ENGINE_BINARY ${prisma-engines_6}/bin/schema-engine
    )
    makeWrapper $lf/web/entrypoint.sh $out/bin/langfuse-web \
      "''${engineEnv[@]}" \
      --set-default NEXT_MANUAL_SIG_HANDLE true \
      --prefix PATH : ${
        lib.makeBinPath [
          prisma_6
          migrate
          openssl # Prisma probes it to pick its OpenSSL variant
        ]
      } \
      --chdir $lf \
      --add-flags "${node}/bin/node $lf/web/server.js --keepAliveTimeout 110000"
    makeWrapper $lf/worker/entrypoint.sh $out/bin/langfuse-worker \
      "''${engineEnv[@]}" \
      --chdir $lf/worker \
      --add-flags "${node}/bin/node $lf/worker/dist/index.js"

    # Prune broken symlinks common in pnpm monorepos
    find $out -type l -xtype l -delete

    runHook postInstall
  '';

  passthru.tests.vm = callPackage ./test.nix { langfuse = finalAttrs.finalPackage; };

  meta = with lib; {
    description = "Open source LLM engineering platform: observability, metrics, eval, prompt management";
    homepage = "https://langfuse.com";
    license = licenses.mit;
    platforms = platforms.linux;
  };
})
