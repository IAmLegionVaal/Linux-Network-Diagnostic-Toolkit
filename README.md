# Linux Network Diagnostic Toolkit

A Linux support toolkit for collecting network evidence and repairing selected interface, DHCP, resolver and network-service problems.

## Diagnostic script

```bash
chmod +x src/linux_network_diagnostic.sh
sudo ./src/linux_network_diagnostic.sh --target example.com
```

The diagnostic script reports interfaces, routes, neighbour tables, DNS, connectivity, sockets, network managers, firewall context and MTU evidence.

## Repair script

Preview standard network service repair:

```bash
chmod +x src/linux_network_repair.sh
sudo ./src/linux_network_repair.sh --repair --dry-run
```

Restart the detected network manager:

```bash
sudo ./src/linux_network_repair.sh --repair
```

Flush resolver caches:

```bash
sudo ./src/linux_network_repair.sh --flush-dns
```

Renew DHCP or cycle one interface:

```bash
sudo ./src/linux_network_repair.sh --interface eth0 --renew-dhcp
sudo ./src/linux_network_repair.sh --interface eth0 --cycle-interface
```

## What the repair does

- Detects NetworkManager, systemd-networkd or the traditional networking service.
- Restarts the active network-management service.
- Flushes resolver caches and restarts supported resolver services.
- Renews DHCP using the active manager or `dhclient` where available.
- Cycles or reconfigures one selected interface.
- Captures before-and-after interface, route, DNS and connectivity state.
- Supports confirmation prompts, dry-run, logs and clear exit codes.

## Safety and limitations

Network repair can interrupt SSH, VPN and remote-management sessions. The tool does not change firewall rules, create routes or write persistent DNS configuration.

## Maintainer

IAmLegionVaal
