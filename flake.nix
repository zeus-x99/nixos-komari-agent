{
  description = "Reusable NixOS module for the Komari monitoring agent";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosModules = {
        default = ./module.nix;
        komari-agent = ./module.nix;
      };

      checks = forAllSystems (system: {
        module-evaluation =
          let
            evaluated = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.default
                {
                  services.komari-agent = {
                    enable = true;
                    endpoint = "https://komari.example.invalid";
                    tokenFile = "/run/secrets/komari-agent-token";
                    autoDiscoveryKeyFile = "/run/secrets/komari-auto-discovery-key";
                    interval = 2.5;
                    disableAutoUpdate = true;
                    disableWebSsh = true;
                    ignoreUnsafeCert = false;
                    maxRetries = 4;
                    reconnectInterval = 6;
                    infoReportInterval = 10;
                    includeNics = "br0,ppp0";
                    excludeNics = "lo";
                    includeMountpoints = "/;/data";
                    monthRotate = 1;
                    memoryIncludeCache = true;
                    memoryReportRawUsed = false;
                    customDns = "119.29.29.29,223.5.5.5";
                    enableGpu = true;
                    showWarning = false;
                    customIpv4 = "10.0.0.1";
                    customIpv6 = "fd00:10::1";
                    getIpAddrFromNic = true;
                    hostProc = "/host/proc";
                    configFile = "/etc/komari-agent.json";
                    disableCompression = true;
                    preferIpVersion = "4";
                    extraArgs = [ "--help" ];
                  };
                }
              ];
            };
            package = nixpkgs.legacyPackages.${system};
          in
          assert evaluated.config.systemd.services.komari-agent.serviceConfig.ExecStart != null;
          assert builtins.elem "CAP_NET_RAW"
            evaluated.config.systemd.services.komari-agent.serviceConfig.CapabilityBoundingSet;
          assert builtins.elem "CAP_NET_RAW"
            evaluated.config.systemd.services.komari-agent.serviceConfig.AmbientCapabilities;
          package.runCommand "komari-agent-module-check" { } ''
            export CREDENTIALS_DIRECTORY="$TMPDIR/credentials"
            mkdir "$CREDENTIALS_DIRECTORY"
            printf '%s\n' test-token > "$CREDENTIALS_DIRECTORY/token"
            printf '%s\n' test-discovery-key > "$CREDENTIALS_DIRECTORY/auto-discovery-key"
            ${evaluated.config.systemd.services.komari-agent.serviceConfig.ExecStart} > agent-help.txt
            grep -Fq 'komari-agent [flags]' agent-help.txt
            touch "$out"
          '';
      });
    };
}
