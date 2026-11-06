{ pkgs }:

pkgs.testers.runNixOSTest {
  name = "komari-agent-terminal-privileges";

  defaults = {
    imports = [ ../module.nix ];

    users.users.alice = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.fish;
    };
    programs.fish = {
      enable = true;
      interactiveShellInit = "set -g komari_test_shell_loaded yes";
    };
    security.sudo.wheelNeedsPassword = false;
    environment.etc."komari-test-token".text = "test-token";

    services.komari-agent = {
      enable = true;
      endpoint = "https://komari.example.invalid";
      tokenFile = "/etc/komari-test-token";
      # Exercise child processes inside the real service sandbox without a server.
      package = pkgs.writeShellScriptBin "komari-agent" ''
        set -eu
        test "$AGENT_TOKEN" = test-token
        id -un > user
        printf '%s\n' "$HOME" > home
        printf '%s\n' "$SHELL" > shell
        command -v bash > fallback-shell
        probe="$(mktemp "$HOME/komari-terminal-test.XXXXXX")"
        rm "$probe"

        case "$SHELL" in
          */fish)
            "$SHELL" -ic 'test "$komari_test_shell_loaded" = yes; or exit 1; echo shell-ok' > shell-result
            ;;
          *) "$SHELL" -c 'echo shell-ok' > shell-result ;;
        esac

        if /run/wrappers/bin/sudo -n ${pkgs.coreutils}/bin/id -u > sudo-uid 2> sudo-error; then
          /run/wrappers/bin/sudo -n /run/wrappers/bin/su \
            -s ${pkgs.bash}/bin/bash nobody \
            -c '${pkgs.coreutils}/bin/id -un' > su-user
          /run/wrappers/bin/sudo -n ${pkgs.coreutils}/bin/touch /etc/komari-admin-probe
        fi

        touch ready
        exec ${pkgs.coreutils}/bin/sleep infinity
      '';
    };
    systemd.services.komari-agent.serviceConfig.Restart = pkgs.lib.mkForce "no";
  };

  nodes = {
    dynamic = { };
    restricted.services.komari-agent.user = "alice";
    privileged.services.komari-agent = {
      user = "alice";
      enableHardening = false;
    };
  };

  testScript = ''
    start_all()

    def service_read(machine, filename):
        pid = machine.succeed("systemctl show komari-agent --property=MainPID --value").strip()
        return machine.succeed(f"cat /proc/{pid}/root/var/lib/komari-agent/{filename}").strip()

    for machine in (dynamic, restricted, privileged):
        machine.wait_for_unit("komari-agent.service")
        pid = machine.succeed("systemctl show komari-agent --property=MainPID --value").strip()
        machine.wait_until_succeeds(f"test -e /proc/{pid}/root/var/lib/komari-agent/ready", timeout=60)
        assert service_read(machine, "shell-result") == "shell-ok"
        assert service_read(machine, "fallback-shell").endswith("/bin/bash")

    with subtest("dynamic user gets a working shell and writable home"):
        assert service_read(dynamic, "user") == "komari-agent"
        assert service_read(dynamic, "home") == "/var/lib/komari-agent"
        assert service_read(dynamic, "shell").endswith("/bin/bash")
        assert service_read(dynamic, "sudo-uid") == ""
        dynamic.fail("test -e /etc/komari-admin-probe")

    with subtest("named user inherits Fish without gaining sudo by default"):
        assert service_read(restricted, "user") == "alice"
        assert service_read(restricted, "home") == "/home/alice"
        assert service_read(restricted, "shell").endswith("/bin/fish")
        assert service_read(restricted, "sudo-uid") == ""
        restricted.fail("test -e /etc/komari-admin-probe")

    with subtest("explicit privilege escalation permits sudo, su and system writes"):
        assert service_read(privileged, "user") == "alice"
        assert service_read(privileged, "shell").endswith("/bin/fish")
        assert service_read(privileged, "sudo-uid") == "0"
        assert service_read(privileged, "su-user") == "nobody"
        privileged.succeed("test -e /etc/komari-admin-probe")
  '';
}
