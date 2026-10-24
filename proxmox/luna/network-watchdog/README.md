# Luna network recovery watchdog

This is a deliberately bounded availability backstop for Luna's observed
e1000e transmit-ring hang. It is not a cure for the onboard NIC.

Every 15 seconds it probes both Luna's LAN gateway (`10.4.1.1`) and an external
IP (`1.1.1.1`) through `vmbr0`, then (after three consecutive dual failures)
resets the physical `nic0` link once. It
waits ten seconds and probes again. Only if the host is
still isolated does it reboot, with a persistent cap of one automatic reboot in
24 hours. The same persistent 24-hour cap covers the entire recovery attempt:
subsequent failed checks cannot reset the NIC again during that window, even
if the first reset recovered connectivity or the reboot request failed. A
reachable gateway or external IP clears the consecutive-failure count and
prevents recovery; an internet-only outage does not trigger it.

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
timer. Inspect it with:

```sh
systemctl status luna-network-watchdog.timer
journalctl -u luna-network-watchdog.service -f
```

## Tests

Run `python3 -m unittest discover -s proxmox/luna/network-watchdog/tests -v`
from the repository root. Tests run a temporary copy with isolated state and
mocked host commands; they never touch the host NIC or request a real reboot.
