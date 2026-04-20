{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpmConfigHook,
  fetchPnpmDeps,
  pnpm_10,
  prisma-engines_6,
  python3,
  pkg-config,
  openssl,
  vips,
  # Build-time environment variables for Next.js frontend
  nextPublicLangfuseCloudRegion ? "EU",
  nextTelemetryDisabled ? "1",
}:

let
  node = nodejs_22;
in
stdenv.mkDerivation rec {
  pname = "langfuse";
  version = "3.167.4";

  src = fetchFromGitHub {
    owner = "langfuse";
    repo = "langfuse";
    rev = "v${version}";
    hash = "sha256-R8Rv4zpQAoM6SN7uyuD0dXqYKYvM41fwKN+DZ/pIENU=";
  };

  nativeBuildInputs = [
    node
    pnpm_10
    pnpmConfigHook
    prisma-engines_6
    python3 # Required for some node-gyp builds
    pkg-config
  ];

  buildInputs = [
    openssl
    vips # Image processing
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    hash = "sha256-6ZiUEitVOQQfYL1MnNoaJTF/fdUcdOpHtvnYIiNOJSY=";
    fetcherVersion = 2; # For pnpm v10
    # Ensure patches are available during the offline fetch
    prePnpmInstall = ''
      cp -r ${src}/patches .
    '';
  };

  # Copy patches before pnpm install in the main build
  preConfigure = ''
    cp -r ${src}/patches .
  '';

  # Required for Next.js build-time configuration and Prisma engines
  env = {
    NEXT_PUBLIC_LANGFUSE_CLOUD_REGION = nextPublicLangfuseCloudRegion;
    NEXT_TELEMETRY_DISABLED = nextTelemetryDisabled;
    DOCKER_BUILD = "1";
    CI = "true";
    NODE_ENV = "production";

    # Point Prisma to the Nix-provided engines
    PRISMA_SCHEMA_ENGINE_BINARY = "${prisma-engines_6}/bin/schema-engine";
    PRISMA_QUERY_ENGINE_BINARY = "${prisma-engines_6}/bin/query-engine";
    PRISMA_QUERY_ENGINE_LIBRARY = "${prisma-engines_6}/lib/libquery_engine.node";
    PRISMA_FMT_BINARY = "${prisma-engines_6}/bin/prisma-fmt";
  };

  buildPhase = ''
    runHook preBuild

    # Generate Prisma client
    pnpm run db:generate

    # Build the monorepo using Turbo
    # We build both web and worker
    npx turbo run build --filter=web --filter=worker

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/langfuse

    # Next.js standalone output for the web app
    cp -r web/.next/standalone/* $out/lib/langfuse/
    cp -r web/.next/static $out/lib/langfuse/web/.next/static
    cp -r web/public $out/lib/langfuse/web/public

    # Worker build
    cp -r worker/dist $out/lib/langfuse/worker

    # Create bin wrappers
    mkdir -p $out/bin

    cat > $out/bin/langfuse-web <<EOF
    #!/bin/sh
    exec ${node}/bin/node $out/lib/langfuse/web/server.js
    EOF

    cat > $out/bin/langfuse-worker <<EOF
    #!/bin/sh
    exec ${node}/bin/node $out/lib/langfuse/worker/index.js
    EOF

    chmod +x $out/bin/langfuse-web $out/bin/langfuse-worker

    # Prune broken symlinks common in pnpm monorepos
    find $out -type l -xtype l -delete

    runHook postInstall
  '';

  meta = with lib; {
    description = "Open source LLM engineering platform: observability, metrics, eval, prompt management";
    homepage = "https://langfuse.com";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
