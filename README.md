# Linux Network Diagnostic Toolkit

A read-only Bash toolkit for collecting Linux network configuration, connectivity, DNS, routing, socket, and firewall evidence.

## Features

- Interface, address, link, route, and neighbour-table inventory
- DNS resolver configuration and name-resolution tests
- Default-gateway, internet, and HTTPS reachability tests
- Packet-loss and latency measurements
- Listening and established socket evidence
- NetworkManager or systemd-networkd status
- Firewall context from UFW, firewalld, or nftables
- MTU and route-to-target analysis
- Text and JSON summary reports

## Usage

```bash
chmod +x src/linux_network_diagnostic.sh
sudo ./src/linux_network_diagnostic.sh
```

Target a specific host:

```bash
sudo ./src/linux_network_diagnostic.sh --target example.com --output /tmp/network-test
```

## Safety

The script does not reset adapters, renew addresses, flush DNS, change routes, or modify firewall rules.

## Validation

Test with working connectivity, failed DNS, unreachable gateway, disconnected interface, and a VPN-enabled lab host.

## Author

Dewald Pretorius — L2 IT Support Engineer
