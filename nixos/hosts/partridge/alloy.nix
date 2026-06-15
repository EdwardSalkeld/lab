{ ... }:

{
  environment.etc."alloy/config.alloy".source = ./alloy/config.alloy;

  services.alloy = {
    enable = true;
    extraFlags = [
      "--disable-reporting"
      "--server.http.listen-addr=127.0.0.1:12345"
    ];
  };

  systemd.services.alloy = {
    after = [ "loki.service" ];
    wants = [ "loki.service" ];
  };
}
