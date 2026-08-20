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
                  };
                }
              ];
            };
            package = nixpkgs.legacyPackages.${system};
          in
          assert evaluated.config.systemd.services.komari-agent.serviceConfig.ExecStart != null;
          package.runCommand "komari-agent-module-check" { } "touch $out";
      });
    };
}
