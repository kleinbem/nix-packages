{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.ente-museum;
in
{
  options.services.ente-museum = {
    enable = mkEnableOption "ente's self-hosted server (museum)";

    package = mkOption {
      type = types.package;
      default = pkgs.ente-museum; # provided by the overlay
      description = "The ente-museum package to use.";
    };

    user = mkOption {
      type = types.str;
      default = "ente-museum";
      description = "User account under which museum runs.";
    };

    group = mkOption {
      type = types.str;
      default = "ente-museum";
      description = "Group account under which museum runs.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "HTTP port to listen on.";
    };

    db = {
      host = mkOption {
        type = types.str;
        default = "localhost";
      };
      port = mkOption {
        type = types.port;
        default = 5432;
      };
      name = mkOption {
        type = types.str;
        default = "ente_db";
      };
      sslmode = mkOption {
        type = types.str;
        default = "disable";
      };
    };

    s3 = {
      endpoint = mkOption {
        type = types.str;
        description = "S3-compatible endpoint (host:port) for the b2-eu-cen bucket slot museum uses by default.";
      };
      region = mkOption {
        type = types.str;
        default = "us-east-1";
      };
      bucket = mkOption {
        type = types.str;
        default = "ente";
      };
      useLocalMinio = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Sets s3.are_local_buckets + s3.use_path_style_urls, which museum's
          own config docs describe as the "workarounds to allow us to use a
          local minio instance for object storage" (disables SSL, uses path-
          style URLs, skips storage-class headers minio doesn't support).
          Leave enabled for a self-hosted MinIO backend, disable for a real
          S3-compatible cloud provider.
        '';
      };
    };

    # Secrets only — everything above is non-sensitive topology. Must set
    # ENTE_DB_PASSWORD, ENTE_KEY_ENCRYPTION, ENTE_KEY_HASH, ENTE_JWT_SECRET,
    # and ENTE_S3_B2_EU_CEN_KEY/ENTE_S3_B2_EU_CEN_SECRET (museum's env-var
    # convention: nesting/hyphens -> underscores, see configurations/
    # local.yaml's header comment in the ente-museum source).
    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing museum's secret ENTE_* environment variables.";
    };
  };

  config = mkIf cfg.enable {
    users.users."${cfg.user}" = {
      isSystemUser = true;
      inherit (cfg) group;
    };
    users.groups."${cfg.group}" = { };

    systemd.services.ente-museum = {
      description = "ente self-hosted server (museum)";
      after = [
        "network.target"
        "postgresql.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        ENTE_HTTP_PORT = toString cfg.port;
        ENTE_DB_HOST = cfg.db.host;
        ENTE_DB_PORT = toString cfg.db.port;
        ENTE_DB_NAME = cfg.db.name;
        ENTE_DB_SSLMODE = cfg.db.sslmode;
        ENTE_S3_B2_EU_CEN_ENDPOINT = cfg.s3.endpoint;
        ENTE_S3_B2_EU_CEN_REGION = cfg.s3.region;
        ENTE_S3_B2_EU_CEN_BUCKET = cfg.s3.bucket;
      }
      // optionalAttrs cfg.s3.useLocalMinio {
        ENTE_S3_ARE_LOCAL_BUCKETS = "true";
        ENTE_S3_USE_PATH_STYLE_URLS = "true";
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/museum";
        # museum resolves configurations/migrations/mail-templates/
        # web-templates via hardcoded relative paths from its CWD — see the
        # package's own doc comment. This is the one directory that has all
        # four alongside the binary.
        WorkingDirectory = "${cfg.package}/share/ente-museum";
        Restart = "always";
        RestartSec = "5s";
        StateDirectory = "ente-museum";

        # Hardening
        ProtectSystem = "full";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
