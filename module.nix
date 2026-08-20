{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    escapeShellArgs
    getExe
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optional
    types
    ;
  cfg = config.services.komari-agent;
  commandLine = [
    "--endpoint"
    cfg.endpoint
  ]
  ++ optional cfg.disableAutoUpdate "--disable-auto-update"
  ++ optional cfg.disableWebSsh "--disable-web-ssh"
  ++ cfg.extraArgs;
  startScript = pkgs.writeShellScript "komari-agent-start" ''
    set -eu

    token="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/token")"
    if [ -z "$token" ]; then
      echo "Komari agent token is empty" >&2
      exit 1
    fi
    export AGENT_TOKEN="$token"
    exec ${getExe cfg.package} ${escapeShellArgs commandLine}
  '';
in
{
  options.services.komari-agent = {
    enable = mkEnableOption "the Komari monitoring agent";

    package = mkPackageOption pkgs "komari-agent" { };

    endpoint = mkOption {
      type = types.str;
      default = "";
      description = "Komari server URL to which the agent reports.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the Komari agent token. The token is loaded
        as a systemd credential and exposed to the agent only through
        AGENT_TOKEN at runtime.
      '';
    };

    disableAutoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Disable Komari's self-update, which cannot modify the Nix store.";
    };

    disableWebSsh = mkOption {
      type = types.bool;
      default = false;
      description = "Disable Komari web SSH and remote command control.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional command-line arguments passed to komari-agent.";
      example = [
        "--include-nics"
        "br0,ppp0"
        "--month-rotate"
        "1"
      ];
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.endpoint != "";
        message = "services.komari-agent.endpoint must be set when the service is enabled.";
      }
      {
        assertion = cfg.tokenFile != null;
        message = "services.komari-agent.tokenFile must be set when the service is enabled.";
      }
    ];

    systemd.services.komari-agent = {
      description = "Komari monitoring agent";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartTriggers = [ startScript ];
      serviceConfig = {
        Type = "simple";
        ExecStart = startScript;
        LoadCredential = [ "token:${cfg.tokenFile}" ];
        StateDirectory = "komari-agent";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/komari-agent";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };
}
