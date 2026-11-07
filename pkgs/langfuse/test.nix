# Boots web and worker through modules/nixos/langfuse.nix against local
# Postgres, Redis and ClickHouse: proves module resolution, the native addon
# and the start-up migrations, not the UI.
{ testers, langfuse }:
testers.runNixOSTest {
  name = "langfuse";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules/nixos/langfuse.nix ];
      virtualisation = {
        memorySize = 6144;
        cores = 4;
        diskSize = 8192;
      };

      services = {
        postgresql = {
          enable = true;
          ensureDatabases = [ "langfuse" ];
          ensureUsers = [
            {
              name = "langfuse";
              ensureDBOwnership = true;
            }
          ];
          authentication = "host langfuse langfuse 127.0.0.1/32 trust";
        };
        redis.servers.langfuse = {
          enable = true;
          port = 6379;
        };
        clickhouse.enable = true;
        langfuse = {
          enable = true;
          package = langfuse;
          environmentFile = pkgs.writeText "langfuse.env" ''
            DATABASE_URL=postgresql://langfuse@127.0.0.1:5432/langfuse
            NEXTAUTH_URL=http://localhost:3000
            NEXTAUTH_SECRET=test-secret
            SALT=test-salt
            ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000
            CLICKHOUSE_URL=http://127.0.0.1:8123
            CLICKHOUSE_MIGRATION_URL=clickhouse://127.0.0.1:9000
            CLICKHOUSE_USER=langfuse
            CLICKHOUSE_PASSWORD=langfuse
            CLICKHOUSE_CLUSTER_ENABLED=false
            REDIS_CONNECTION_STRING=redis://127.0.0.1:6379
            LANGFUSE_S3_EVENT_UPLOAD_BUCKET=langfuse
            TELEMETRY_ENABLED=false
          '';
        };
      };
      environment.systemPackages = [ pkgs.clickhouse ];
      # up.sh refuses an empty CLICKHOUSE_PASSWORD.
      environment.etc."clickhouse-server/users.d/langfuse.xml".text = ''
        <clickhouse><users><langfuse>
          <password>langfuse</password>
          <networks><ip>::/0</ip></networks>
          <profile>default</profile><quota>default</quota>
          <access_management>1</access_management>
        </langfuse></users></clickhouse>
      '';

      systemd.services.langfuse = {
        after = [
          "clickhouse.service"
          "redis-langfuse.service"
        ];
        wants = [
          "clickhouse.service"
          "redis-langfuse.service"
        ];
      };
    };

  testScript = ''
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("clickhouse.service")
    machine.wait_for_unit("langfuse.service")
    machine.wait_for_unit("langfuse-worker.service")

    # Web runs the Postgres and ClickHouse migrations before it listens.
    machine.wait_for_open_port(3000, timeout=600)
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:3000/api/public/health", timeout=300)
    machine.succeed("sudo -u postgres psql -d langfuse -tAc 'select count(*) from _prisma_migrations' | grep -v '^0$'")
    machine.succeed("clickhouse-client --user langfuse --password langfuse -q 'exists table traces' | grep -x 1")

    # Worker loads @langfuse/native and serves its health endpoint.
    machine.wait_for_open_port(3030, timeout=300)
    machine.wait_until_succeeds("curl -fsS http://127.0.0.1:3030/api/health", timeout=300)

    journal = machine.succeed("journalctl -u langfuse -u langfuse-worker --no-pager")
    for bad in ["Cannot find module", "ERR_MODULE_NOT_FOUND", "ERR_DLOPEN_FAILED"]:
        assert bad not in journal, f"{bad} in the Langfuse journal"
  '';
}
