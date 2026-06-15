{ pkgs, ... }:

let
  yaml = pkgs.formats.yaml { };
  houseRoot = "/home/edward/develop/house";
  chattingRoot = "/home/edward/develop/chatting";
  blinkDockerRoot = "${houseRoot}/blink/docker";

  blinkCompose = yaml.generate "blink-compose.yml" {
    services = {
      pigallery2 = {
        image = "bpatrik/pigallery2:latest";
        container_name = "photos";
        environment = [ "NODE_ENV=production" ];
        volumes = [
          "${blinkDockerRoot}/pigallery2/config:/app/data/config"
          "pigallery2-storage:/app/data/db"
          "/mnt/ssd4tb/full/photos/archive:/app/data/images:ro"
          "${blinkDockerRoot}/pigallery2/tmp:/app/data/tmp"
        ];
        expose = [ "80" ];
        ports = [ "3456:80" ];
        restart = "always";
      };

      scheduler = {
        build = {
          context = "${houseRoot}/blink/scheduler";
          args = {
            UID = "\${UID:-1000}";
            GID = "\${GID:-1000}";
          };
        };
        container_name = "scheduler";
        user = "\${UID:-1000}:\${GID:-1000}";
        restart = "unless-stopped";
        volumes = [
          "${houseRoot}/blink/scheduler/.env:/app/.env"
          "${houseRoot}/blink/linear-issues:/linear"
        ];
        env_file = [ "${houseRoot}/blink/scheduler/.env" ];
        command = [ "/app/scheduler" ];
      };

    };

    volumes = {
      pigallery2-storage = null;
    };

  };

  composeService = name: root: composeFile: extraConfig: {
    description = "Docker Compose stack: ${name}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [
      "docker.service"
      "network-online.target"
    ];
    path = [
      pkgs.docker
      pkgs.docker-compose
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = root;
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} down";
      TimeoutStartSec = "15min";
    };
  } // extraConfig;
in
{
  systemd.services.blink-compose = composeService "blink" blinkDockerRoot blinkCompose {
    requiresMountsFor = [
      "/mnt/ext2tb/1"
      "/mnt/ext2tb/3"
      "/mnt/ext2tb/4"
      "/mnt/ssd4tb"
      "/mnt/redhdd"
    ];
  };

  systemd.services.chatting-compose = composeService "chatting" chattingRoot "${chattingRoot}/docker-compose.yml" { };
}
