{ nixpkgs, system }:

let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};
  evaluate =
    settings:
    (lib.nixosSystem {
      inherit system;
      modules = [
        ../module.nix
        {
          system.stateVersion = "26.05";
          users.users.alice.isNormalUser = true;
          services.komari-agent = {
            enable = true;
            endpoint = "https://komari.example.invalid";
            tokenFile = "/run/secrets/komari-agent-token";
            user = "alice";
          }
          // settings;
        }
      ];
    }).config;
  unit = config: config.systemd.units."komari-agent.service".text;
  restricted = evaluate { enableHardening = true; };
  anonymous = evaluate {
    user = null;
    enableHardening = false;
  };
  rejects =
    settings: !(builtins.tryEval (evaluate settings).services.komari-agent.enableHardening).success;
in
assert unit (evaluate { }) == unit restricted;
assert rejects { allowPrivilegeEscalation = false; };
assert rejects { allowPrivilegeEscalation = true; };
assert rejects {
  allowPrivilegeEscalation = true;
  enableHardening = false;
};
assert rejects { enableHardening = "false"; };
assert lib.any (
  entry:
  !entry.assertion
  && entry.message == "Disabling services.komari-agent.enableHardening requires an explicit user."
) anonymous.assertions;
pkgs.runCommand "komari-agent-option-validation-check" { } ''
  touch "$out"
''
