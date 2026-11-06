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
  privileged = evaluate { enableHardening = false; };
  legacyRestricted = evaluate { allowPrivilegeEscalation = false; };
  legacyPrivileged = evaluate { allowPrivilegeEscalation = true; };
  conflicting = evaluate {
    enableHardening = true;
    allowPrivilegeEscalation = true;
  };
  anonymous = evaluate {
    user = null;
    enableHardening = false;
  };
  warnsAboutMigration =
    config:
    lib.any (
      warning: lib.hasInfix "allowPrivilegeEscalation" warning && lib.hasInfix "enableHardening" warning
    ) config.warnings;
in
assert unit (evaluate { }) == unit restricted;
assert unit legacyRestricted == unit restricted;
assert unit legacyPrivileged == unit privileged;
assert warnsAboutMigration legacyRestricted;
assert warnsAboutMigration legacyPrivileged;
assert !warnsAboutMigration privileged;
assert !(builtins.tryEval conflicting.services.komari-agent.enableHardening).success;
assert lib.any (
  entry:
  !entry.assertion
  && entry.message == "Disabling services.komari-agent.enableHardening requires an explicit user."
) anonymous.assertions;
pkgs.runCommand "komari-agent-option-compatibility-check" { } ''
  touch "$out"
''
