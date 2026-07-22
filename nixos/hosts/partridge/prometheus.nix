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
        job_name = "billy";
        scrape_interval = "5s";
        static_configs = [
          { targets = [ "blink.int.alcachofa.faith:9464" ]; }
        ];
      }
      {
        # wantlist (music want-list app) on blink. Scraped through its Traefik vhost over HTTPS
        # rather than a direct port: the app publishes no host port (only the reverse-proxy
        # network), and 8000 isn't in blink's firewall allow-list. The FastAPI app serves
        # /metrics on the same origin as the UI.
        job_name = "wantlist";
        scheme = "https";
        metrics_path = "/metrics";
        static_configs = [
          { targets = [ "wantlist.b.alcachofa.faith:443" ]; }
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
              "magpie.int.alcachofa.faith:9100"
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
        job_name = "opnsense";
        static_configs = [
          { targets = [ "127.0.0.1:8080" ]; }
        ];
      }
      {
        # node_exporter plugin on the OPNsense box itself. Separate label from
        # the Linux `node` job because OPNsense is FreeBSD and exposes different
        # metric names (no node_memory_MemAvailable_bytes etc.).
        job_name = "opnsense-node";
        static_configs = [
          { targets = [ "10.4.1.1:9100" ]; }
        ];
      }
    ];
  };

}
