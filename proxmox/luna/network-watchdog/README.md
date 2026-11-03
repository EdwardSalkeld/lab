# Luna network recovery watchdog

This is a deliberately bounded availability backstop for Luna's observed
e1000e transmit-ring hang. It is not a cure for the onboard NIC.

Every 15 seconds it checks Sol (`10.4.1.32`), Partridge (`10.4.1.30`) and Magpie
(`10.4.1.31`), followed by Luna's LAN gateway (`10.4.1.1`) and an external IP
(`1.1.1.1`), stopping on the first response. All probes bind to `vmbr0` and use
IP addresses, so DNS and an alternate route cannot mask the result. The peers
are on Luna's side of the bridging router and on another physical host; Kite
is deliberately excluded because a local VM would not exercise the NIC.

Any reachable target clears the failure count and prevents both NIC resets and
reboots. A bridging-router outage with Sol or either of its VMs still reachable
therefore causes no recovery action. Only after three consecutive failures of
**every** target does it collect evidence, recheck connectivity, and reset the
physical `nic0` link once. It
waits ten seconds and probes again. Only if the host is
still isolated does it reboot, with a persistent cap of one automatic reboot in
24 hours. The same persistent 24-hour cap covers the entire recovery attempt:
subsequent failed checks cannot reset the NIC again during that window, even
if the first reset recovered connectivity or the reboot request failed. A
reachable peer, gateway or external IP after the reset prevents rebooting too.

Before resetting the link it writes timestamped local evidence under
`/var/log/luna-network-watchdog/`: NIC counters and state, routes, ethtool
details, and relevant kernel messages. The failed-probe count and reboot cap
live under `/var/lib/luna-network-watchdog/`, so a reboot cannot bypass them.
Upgrades also honour an existing automatic-reboot timestamp. The
`reboot_cooldown_seconds` setting controls the recovery cap, including resets.

The included configuration is intentionally specific to Luna's current static
network. To change its addresses or timings, edit `/etc/default/luna-network-watchdog`.

## Installation

After this change is merged, copy this directory from the reviewed checkout to
Luna and run `install.sh` as root. It refuses to run on any host other than
`luna`, preserves an existing configuration file, and enables the systemd
timer.

The new peer defaults are also in the script, so reinstalling updates the
behaviour even when preserving an older config without `lan_peers`. An explicit
`lan_peers=(...)` setting overrides those defaults. Merging this PR does not
install the host-side assets automatically; run the installer on Luna.

Inspect it with:

```sh
systemctl status luna-network-watchdog.timer
journalctl -u luna-network-watchdog.service -f
```

## Tests

Run `python3 -m unittest discover -s proxmox/luna/network-watchdog/tests -v`
from the repository root. Tests run a temporary copy with isolated state and
mocked host commands; they never touch the host NIC or request a real reboot.
