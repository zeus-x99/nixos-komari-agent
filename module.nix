{
  config,
  lib,
  pkgs,
  utils,
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
    optionalAttrs
    optionalString
    optionals
    types
    ;
  cfg = config.services.komari-agent;
  serviceUser = if cfg.user == null then null else config.users.users.${cfg.user} or null;
  shell =
    if serviceUser != null && serviceUser.shell != null then
      serviceUser.shell
    else
      pkgs.bashInteractive;
  optionalArgument =
    name: value:
    optionals (value != null) [
      name
      (toString value)
    ];
  commandLine = [
    "--endpoint"
    cfg.endpoint
    "--interval"
    (toString cfg.interval)
    "--max-retries"
    (toString cfg.maxRetries)
    "--reconnect-interval"
    (toString cfg.reconnectInterval)
    "--info-report-interval"
    (toString cfg.infoReportInterval)
    "--month-rotate"
    (toString cfg.monthRotate)
  ]
  ++ optional cfg.disableAutoUpdate "--disable-auto-update"
  ++ optional cfg.disableWebSsh "--disable-web-ssh"
  ++ optional cfg.ignoreUnsafeCert "--ignore-unsafe-cert"
  ++ optional cfg.memoryIncludeCache "--memory-include-cache"
  ++ optional cfg.memoryReportRawUsed "--memory-exclude-bcf"
  ++ optional cfg.enableGpu "--gpu"
  ++ optional cfg.showWarning "--show-warning"
  ++ optional cfg.getIpAddrFromNic "--get-ip-addr-from-nic"
  ++ optional cfg.disableCompression "--disable-compression"
  ++ optionalArgument "--custom-dns" cfg.customDns
  ++ optionalArgument "--custom-ipv4" cfg.customIpv4
  ++ optionalArgument "--custom-ipv6" cfg.customIpv6
  ++ optionalArgument "--include-nics" cfg.includeNics
  ++ optionalArgument "--exclude-nics" cfg.excludeNics
  ++ optionalArgument "--include-mountpoint" cfg.includeMountpoints
  ++ optionalArgument "--config" cfg.configFile
  ++ optionalArgument "--protocol-version" cfg.protocolVersion
  ++ optionalArgument "--prefer-ip-version" cfg.preferIpVersion
  ++ cfg.extraArgs;
  startScript = pkgs.writeShellScript "komari-agent-start" ''
    set -eu

    token="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/token")"
    if [ -z "$token" ]; then
      echo "Komari agent token is empty" >&2
      exit 1
    fi
    export AGENT_TOKEN="$token"
    ${optionalString (cfg.autoDiscoveryKeyFile != null) ''
      auto_discovery_key="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/auto-discovery-key")"
      if [ -n "$auto_discovery_key" ]; then
        export AGENT_AUTO_DISCOVERY_KEY="$auto_discovery_key"
      fi
    ''}
    exec ${getExe cfg.package} ${escapeShellArgs commandLine}
  '';
in
{
  imports = [
    (lib.mkChangedOptionModule
      [ "services" "komari-agent" "allowPrivilegeEscalation" ]
      [ "services" "komari-agent" "enableHardening" ]
      (config: !config.services.komari-agent.allowPrivilegeEscalation)
    )
  ];

  options.services.komari-agent = {
    enable = mkEnableOption "the Komari monitoring agent";

    package = mkPackageOption pkgs "komari-agent" { };

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "alice";
      description = ''
        Existing user declared in users.users to run the agent and remote
        commands as. Uses that user's home, group and login shell, and allows
        writes to their home. Null uses a restricted dynamic user with Bash
        and /var/lib/komari-agent as its home.
      '';
    };

    enableHardening = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable systemd hardening, including privilege escalation prevention,
        read-only system mounts and syscall restrictions. Set to false to
        allow remote administration using the selected user's existing sudo
        and su permissions. Disabling hardening requires user to be set and
        applies to the whole agent, not only its terminals. It does not grant
        sudo rights or bypass PAM authentication.
      '';
    };

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

    autoDiscoveryKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional file containing the Komari auto-discovery key. It is loaded
        as a systemd credential and exposed as AGENT_AUTO_DISCOVERY_KEY.
      '';
    };

    interval = mkOption {
      type = types.float;
      default = 3.0;
      description = "Data collection interval in seconds.";
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

    ignoreUnsafeCert = mkOption {
      type = types.bool;
      default = false;
      description = "Ignore TLS certificate validation errors.";
    };

    maxRetries = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum number of WebSocket connection retries.";
    };

    reconnectInterval = mkOption {
      type = types.int;
      default = 5;
      description = "Reconnect interval in seconds.";
    };

    infoReportInterval = mkOption {
      type = types.int;
      default = 5;
      description = "Basic information report interval in minutes.";
    };

    includeNics = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Comma-separated network interfaces to include.";
    };

    excludeNics = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Comma-separated network interfaces to exclude.";
    };

    includeMountpoints = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Semicolon-separated mount points to include for disk statistics.";
    };

    monthRotate = mkOption {
      type = types.int;
      default = 0;
      description = "Day of month for traffic counter reset; zero disables it.";
    };

    memoryIncludeCache = mkOption {
      type = types.bool;
      default = false;
      description = "Include cache and buffers in reported memory usage.";
    };

    memoryReportRawUsed = mkOption {
      type = types.bool;
      default = false;
      description = "Report memory as total minus free, buffers, and cached memory.";
    };

    customDns = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom DNS server or comma-separated DNS servers.";
    };

    enableGpu = mkOption {
      type = types.bool;
      default = false;
      description = "Enable detailed GPU monitoring.";
    };

    showWarning = mkOption {
      type = types.bool;
      default = false;
      description = "Show the Komari security warning and exit.";
    };

    customIpv4 = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom IPv4 address to report.";
    };

    customIpv6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom IPv6 address to report.";
    };

    getIpAddrFromNic = mkOption {
      type = types.bool;
      default = false;
      description = "Get the reported IP address from the selected network interface.";
    };

    hostProc = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Alternative proc filesystem path, useful when monitoring a host from a container.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional JSON configuration file passed to Komari. Values in this file
        are applied after the module's command-line and environment settings.
      '';
    };

    protocolVersion = mkOption {
      type = types.nullOr (
        types.enum [
          1
          2
        ]
      );
      default = null;
      description = ''
        Reporting protocol override for older agents that support
        --protocol-version. Leave null for current agents such as 1.5.11,
        which do not accept this flag, to use the agent's default.
      '';
    };

    disableCompression = mkOption {
      type = types.bool;
      default = false;
      description = "Disable v2 gzip and per-message compression.";
    };

    preferIpVersion = mkOption {
      type = types.nullOr (
        types.enum [
          "4"
          "6"
        ]
      );
      default = null;
      description = "Prefer IPv4 or IPv6 for dashboard connections.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional command-line arguments passed to komari-agent.";
      example = [
        "--include-nics"
        "br0,ppp0"
      ];
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user == null || serviceUser != null;
        message = "services.komari-agent.user must name an existing users.users entry.";
      }
      {
        assertion = cfg.enableHardening || cfg.user != null;
        message = "Disabling services.komari-agent.enableHardening requires an explicit user.";
      }
      {
        assertion = cfg.endpoint != "";
        message = "services.komari-agent.endpoint must be set when the service is enabled.";
      }
      {
        assertion = cfg.tokenFile != null;
        message = "services.komari-agent.tokenFile must be set when the service is enabled.";
      }
      {
        assertion = cfg.interval > 0;
        message = "services.komari-agent.interval must be greater than zero.";
      }
      {
        assertion = cfg.maxRetries >= 0;
        message = "services.komari-agent.maxRetries must not be negative.";
      }
      {
        assertion = cfg.reconnectInterval > 0;
        message = "services.komari-agent.reconnectInterval must be greater than zero.";
      }
      {
        assertion = cfg.infoReportInterval > 0;
        message = "services.komari-agent.infoReportInterval must be greater than zero.";
      }
      {
        assertion = cfg.monthRotate >= 0 && cfg.monthRotate <= 31;
        message = "services.komari-agent.monthRotate must be between 0 and 31.";
      }
    ];

    systemd.services.komari-agent = {
      description = "Komari monitoring agent";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartTriggers = [ startScript ];
      path = [
        pkgs.bashInteractive
      ]
      ++ optional (serviceUser != null && lib.isDerivation shell) shell
      ++ optionals (serviceUser != null) [
        "/run/wrappers"
        "/etc/profiles/per-user/${cfg.user}"
        "/run/current-system/sw"
      ];
      environment = {
        HOME = if serviceUser != null then serviceUser.home else "/var/lib/komari-agent";
        SHELL = utils.toShellPath shell;
      }
      // optionalAttrs (cfg.hostProc != null) {
        HOST_PROC = toString cfg.hostProc;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = startScript;
        LoadCredential = [
          "token:${cfg.tokenFile}"
        ]
        ++ optional (cfg.autoDiscoveryKeyFile != null) "auto-discovery-key:${cfg.autoDiscoveryKeyFile}";
        StateDirectory = "komari-agent";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/komari-agent";
        DynamicUser = serviceUser == null;
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        AmbientCapabilities = [ "CAP_NET_RAW" ];
        NoNewPrivileges = cfg.enableHardening;
        ProtectHome = if serviceUser != null then false else "read-only";
      }
      // optionalAttrs (serviceUser != null) {
        User = cfg.user;
        Group = serviceUser.group;
        ReadWritePaths = [ serviceUser.home ];
      }
      // optionalAttrs cfg.enableHardening {
        CapabilityBoundingSet = [ "CAP_NET_RAW" ];
        PrivateTmp = true;
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
