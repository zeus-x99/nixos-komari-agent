# nixos-komari-agent

Reusable NixOS module for running the [`komari-agent`](https://github.com/komari-monitor/komari-agent) package as a hardened systemd service.

## Usage

Add the flake input and module to a NixOS configuration:

```nix
inputs.komari-agent.url = "github:zeus-x99/nixos-komari-agent";

modules = [
  inputs.komari-agent.nixosModules.default
];
```

Configure the service with a token file. The token file should contain only
the token, without a variable name. With sops-nix:

```nix
sops.secrets."komari-agent-token" = {
  sopsFile = ./sops/komari.yaml;
  restartUnits = [ "komari-agent.service" ];
};

services.komari-agent = {
  enable = true;
  endpoint = "https://komari.example.com";
  tokenFile = config.sops.secrets."komari-agent-token".path;
  disableWebSsh = true;
  extraArgs = [
    "--include-nics"
    "br0,ppp0"
  ];
};
```

The module stores Komari's persistent traffic data in
`/var/lib/komari-agent`, loads the token through a systemd credential, and
disables Komari self-updates by default because the package lives in the
immutable Nix store.

## Options

All non-deprecated Komari 1.2.60 settings have typed Nix options:

```text
endpoint tokenFile autoDiscoveryKeyFile interval disableAutoUpdate
disableWebSsh ignoreUnsafeCert maxRetries reconnectInterval infoReportInterval
includeNics excludeNics includeMountpoints monthRotate memoryIncludeCache
memoryReportRawUsed customDns enableGpu showWarning customIpv4 customIpv6
getIpAddrFromNic hostProc configFile protocolVersion disableCompression
preferIpVersion
```

`protocolVersion` defaults to `null`, so the module uses the agent's default
protocol without passing `--protocol-version`. Current agents such as 1.5.11
do not accept that flag. Set this option to `1` or `2` only when using an older
agent package that supports it.

`tokenFile` and `autoDiscoveryKeyFile` contain raw credentials and are loaded
through systemd credentials. `hostProc` is exported as `HOST_PROC`, while
`configFile` points to Komari's JSON configuration file; values in that JSON
file take precedence over the typed command-line options. `extraArgs` remains
available for forward compatibility with newer agent versions. The deprecated
`MemoryModeAvailable` setting is intentionally not exposed. The module grants
`CAP_NET_RAW` to the service for ICMP echo probes and keeps other capabilities
out of the service's bounding set.

Run `nix flake check` after adding the input and before switching the system.
