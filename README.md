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

Run `nix flake check` after adding the input and before switching the system.
