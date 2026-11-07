{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.langfuse;
in
{
  options.services.langfuse = {
    enable = mkEnableOption "Langfuse server";

    package = mkOption {
      type = types.package;
      default = pkgs.langfuse; # Will be provided by overlay
      description = "The Langfuse package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "langfuse";
      description = "User account under which Langfuse runs.";
    };

    group = mkOption {
      type = types.str;
      default = "langfuse";
      description = "Group account under which Langfuse runs.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port to listen on.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File containing environment variables for Langfuse: at least
        DATABASE_URL, NEXTAUTH_URL, NEXTAUTH_SECRET, SALT, ENCRYPTION_KEY,
        CLICKHOUSE_URL, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD,
        REDIS_CONNECTION_STRING and LANGFUSE_S3_EVENT_UPLOAD_BUCKET.

        The web service applies the Postgres and ClickHouse migrations before
        it starts, so it also needs CLICKHOUSE_MIGRATION_URL
        (clickhouse://host:9000). Set LANGFUSE_AUTO_POSTGRES_MIGRATION_DISABLED
        or LANGFUSE_AUTO_CLICKHOUSE_MIGRATION_DISABLED to "true" only when
        migrations are run some other way.
      '';
    };

    clickhouse = {
      enable = mkEnableOption "Clickhouse support for Langfuse";
      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Clickhouse server address.";
      };
    };
  };

  config = mkIf cfg.enable {
    users.users."${cfg.user}" = {
      isSystemUser = true;
      inherit (cfg) group;
      home = "/var/lib/langfuse";
      createHome = true;
    };

    users.groups."${cfg.group}" = { };

    systemd.services.langfuse = {
      description = "Langfuse Web Server";
      after = [
        "network.target"
        "postgresql.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
        HOSTNAME = "0.0.0.0";
        NODE_ENV = "production";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/langfuse-web";
        Restart = "always";
        StateDirectory = "langfuse";
        WorkingDirectory = "/var/lib/langfuse";

        # Hardening
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.langfuse-worker = {
      description = "Langfuse Background Worker";
      after = [
        "network.target"
        "postgresql.service"
        "langfuse.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        NODE_ENV = "production";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/langfuse-worker";
        Restart = "always";
        WorkingDirectory = "/var/lib/langfuse";

        # Hardening
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # Optional Clickhouse local instance if enabled (common for small setups)
    services.clickhouse = mkIf cfg.clickhouse.enable {
      enable = true;
    };
  };
}
