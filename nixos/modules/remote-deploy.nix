# Lets the orchestrator (fourth) trigger a constrained deploy command on THIS
# host. Most hosts expose only `lab-switch`, which rebuilds from the public flake
# on GitHub. `blink` also exposes `chatting-deploy <commit-sha>` so fourth can
# update the Chatting checkout and restart the compose stack with the matching
# pinned GHCR image.
# Build-on-target: fourth is aarch64 and can't build x86 closures, so each host
# builds its own. A compromise of fourth's onward key can therefore only trigger
# the allowed repo-owned deploy commands, never obtain a shell.
{ config, pkgs, ... }:
let
  host = config.networking.hostName;
  labSwitch = pkgs.writeShellScript "lab-switch" ''
    set -euo pipefail
    exec /run/current-system/sw/bin/nixos-rebuild \
      switch --flake "github:EdwardSalkeld/lab#${host}" --refresh
  '';
  chattingDeploy =
    if host == "blink" then
      pkgs.writeShellScript "chatting-deploy" ''
        set -euo pipefail

        target_sha="''${1:-}"
        case "$target_sha" in
          [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
            ;;
          *)
            echo "usage: chatting-deploy <40-char commit sha>" >&2
            exit 64
            ;;
        esac

        repo=/home/edward/develop/chatting
        short_sha="''${target_sha:0:7}"
        image="ghcr.io/edwardsalkeld/chatting:sha-''${short_sha}"

        sudo -u edward git -C "$repo" fetch --quiet origin main
        sudo -u edward git -C "$repo" clean -ffdx

        if ! sudo -u edward git -C "$repo" merge-base --is-ancestor "$target_sha" origin/main; then
          echo "refusing to deploy chatting@$short_sha because it is not on origin/main" >&2
          exit 65
        fi

        sudo -u edward git -C "$repo" checkout --quiet --force "$target_sha"

        actual_sha="$(sudo -u edward git -C "$repo" rev-parse HEAD)"
        if [ "$actual_sha" != "$target_sha" ]; then
          echo "expected chatting@$target_sha on blink, got chatting@$actual_sha after checkout" >&2
          exit 65
        fi

        sudo -u edward env CHATTING_RUNTIME_IMAGE="$image" sh -lc '
          set -euo pipefail
          cd /home/edward/develop/chatting
          docker compose pull handler worker site
          docker compose up -d --build bbmb handler worker site
        '

        curl -fsS http://127.0.0.1:9464/metrics >/dev/null
        curl -fsS http://127.0.0.1:9465/activity.json >/dev/null
        curl -fsS http://127.0.0.1:9466/ >/dev/null
        curl -fsS http://127.0.0.1:9877/metrics >/dev/null
      ''
    else
      null;
  deployDispatch = pkgs.writeShellScript "remote-deploy-dispatch" ''
    set -euo pipefail

    case "''${SSH_ORIGINAL_COMMAND:-}" in
      lab-switch)
        exec ${labSwitch}
        ;;
  ''
  + (if host == "blink" then ''
    "chatting-deploy "*)
      target_sha="''${SSH_ORIGINAL_COMMAND#chatting-deploy }"
      exec ${chattingDeploy} "$target_sha"
      ;;
  '' else "")
  + ''
      *)
        echo "unsupported deploy command: ''${SSH_ORIGINAL_COMMAND:-<empty>}" >&2
        exit 64
        ;;
    esac
  '';
  # fourth's onward deploy public key — from creds/onward_ed25519.pub on fourth.
  fourthDeployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHQr6Slpjl/R7ZMoIf9CWb/Mmwjn5MaFXTpyqxUE952 fourth-deploy";
in
{
  users.users.root.openssh.authorizedKeys.keys = [
    "command=\"${deployDispatch}\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-pty ${fourthDeployKey}"
  ];
}
