# Archer C9 logs in Loki

Partridge's existing Alloy agent receives the bridge router's legacy RFC3164
syslog over UDP 1514 and forwards it to the local Loki writer. The firewall
allows this port only from `10.4.1.2` to `10.4.1.30`; the pipeline also filters
by sender IP. No additional service or privileged listener port is needed.

## Router-side setup after deployment

Once the Partridge configuration is deployed, set the DD-WRT Syslogd **Remote
Server** field to `10.4.1.30:1514` and apply it through the router UI. Its existing
BusyBox syslogd supports `HOST:PORT`, and DD-WRT's `-L` option keeps local logging
enabled alongside forwarding. Enable Klogd too if kernel/driver events should
be included. Router-side settings are applied manually; this module changes
only Partridge.

In Grafana Explore, select Loki and query:

```logql
{host="archer-c9", source="syslog"}
```

Records include `level`, `facility`, `program` and `sender_ip` labels. Receive
timestamps are used so a missing year or incorrect clock on the router doesn't
cause Loki to reject otherwise useful records. Messages received by Loki use
its existing 30-day retention on its dedicated disk.

The wired path to Partridge does not depend on the router's wireless uplink.
UDP is best effort: it cannot guarantee delivery during a complete router
freeze, receiver outage or packet loss. Logs already stored in Loki survive a
router reboot.

## Validation

`nix build --no-link .#checks.x86_64-linux.router-syslog` validates the rendered
configuration with the configured Alloy package, then runs the receiver on
temporary loopback ports. It tests RFC3164 with and without a hostname,
kernel-style messages, label preservation and rejection of another sender.
It uses an echo sink and never connects to production Loki or the router.
