# Proxmox host journal forwarding

Sol and Luna run Proxmox on Debian. This versioned installer pins Grafana Alloy
1.16.0 and its release checksum, validates the configuration, and enables a
dedicated service. It ships the systemd journal to the Lab Loki endpoint using
the same host, source, systemd unit and priority labels as the NixOS hosts.
The journal reader runs as root to read the complete host journal. Alloy's web
listener binds to loopback and its journal position is stored persistently.

Run `bash install.sh` as root from this directory on each host. Re-running it
reconciles the pinned binary and configuration. The installer requires curl,
Python 3, systemd and access to GitHub and the Loki endpoint. It only accepts
the hostnames `sol` and `luna`. To remove, disable and stop
`proxmox-journal-alloy.service`, then remove its service, binary, configuration
and state directories.
