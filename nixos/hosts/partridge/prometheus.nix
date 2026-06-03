{ ... }:

let
  prometheusDomain = "prometheus.int.alcachofa.faith";
  prometheusPort = 9090;
in
{
  fileSystems."/var/lib/prometheus" = {
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi4";
    fsType = "ext4";
  };

  alcachofa.partridge.reverseProxy.routes.${prometheusDomain}.port = prometheusPort;

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = prometheusPort;
    stateDir = "prometheus";

    globalConfig = {
      scrape_interval = "15s";
    };

    scrapeConfigs = [
      {
        job_name = "prometheus-self";
        static_configs = [
          { targets = [ "localhost:9090" ]; }
        ];
      }
      {
        job_name = "bbmb";
        scrape_interval = "5s";
        static_configs = [
          { targets = [ "blink.int.alcachofa.faith:9877" ]; }
        ];
      }
      {
        job_name = "cadvisor";
        scrape_interval = "5s";
        static_configs = [
          {
            targets = [
              "blink.int.alcachofa.faith:8083"
              "fourth.int.alcachofa.faith:8080"
              "falcon.ts.alcachofa.faith:8080"
            ];
          }
        ];
      }
      {
        job_name = "node";
        static_configs = [
          {
            targets = [
              "fourth.int.alcachofa.faith:9100"
              "blink.int.alcachofa.faith:9100"
              "sol.int.alcachofa.faith:9100"
              "falcon.ts.alcachofa.faith:9100"
              "partridge.int.alcachofa.faith:9100"
            ];
          }
        ];
      }
      {
        job_name = "partridge-postgres";
        static_configs = [
          { targets = [ "partridge.int.alcachofa.faith:9187" ]; }
        ];
      }
      {
        job_name = "pve";
        metrics_path = "/pve";
        static_configs = [
          { targets = [ "sol.int.alcachofa.faith:9221" ]; }
        ];
      }
      {
        job_name = "alcachofa-prom";
        scrape_interval = "5s";
        scheme = "https";
        basic_auth = {
          username = "edward";
          password = "not-a-real-password";
        };
        static_configs = [
          { targets = [ "prom.alcachofa.faith:8443" ]; }
        ];
      }
    ];
  };

}
