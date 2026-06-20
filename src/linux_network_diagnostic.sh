#!/usr/bin/env bash
set -u

TARGET="1.1.1.1"
DNS_NAME="example.com"
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --dns-name) DNS_NAME="${2:-}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--target HOST] [--dns-name NAME] [--output DIR]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./linux-network-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/network-report.txt"
JSON="$OUTPUT_DIR/network-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"

section() { local title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
have() { command -v "$1" >/dev/null 2>&1; }

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; id'
section "Interfaces and addresses" bash -c 'ip -br link; ip -br addr'
section "Routing table" ip route show table all
section "Policy rules" ip rule show
section "Neighbour table" ip neigh show
section "Resolver configuration" bash -c 'cat /etc/resolv.conf; resolvectl status 2>/dev/null || true'
section "Link details" ip -s link
section "Listening sockets" bash -c 'ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || true'
section "Established sockets" bash -c 'ss -tpn state established 2>/dev/null | head -n 200 || true'
section "Gateway test" bash -c 'gw=$(ip route | awk "/default/ {print \$3; exit}"); echo "Gateway: $gw"; [[ -n "$gw" ]] && ping -c 4 -W 2 "$gw"'
section "Target test" ping -c 4 -W 2 "$TARGET"
section "Route to target" bash -c "ip route get '$TARGET'; traceroute -m 15 '$TARGET' 2>/dev/null || tracepath '$TARGET' 2>/dev/null || true"
section "DNS test" bash -c "getent ahosts '$DNS_NAME'; resolvectl query '$DNS_NAME' 2>/dev/null || nslookup '$DNS_NAME' 2>/dev/null || dig '$DNS_NAME' 2>/dev/null || true"
section "HTTPS test" bash -c "curl -I --connect-timeout 8 --max-time 15 'https://$DNS_NAME' 2>/dev/null || wget --spider --timeout=15 'https://$DNS_NAME' 2>/dev/null || true"

if have nmcli; then section "NetworkManager" nmcli general status; section "NetworkManager devices" nmcli device status; fi
if have networkctl; then section "systemd-networkd" networkctl status --all --no-pager; fi
if have ufw; then section "UFW firewall" ufw status verbose; fi
if have firewall-cmd; then section "firewalld" bash -c 'firewall-cmd --state; firewall-cmd --get-active-zones; firewall-cmd --list-all'; fi
if have nft; then section "nftables" nft list ruleset; fi

GATEWAY="$(ip route | awk '/default/ {print $3; exit}')"
PING_OK=false
ping -c 1 -W 2 "$TARGET" >/dev/null 2>&1 && PING_OK=true
DNS_OK=false
getent hosts "$DNS_NAME" >/dev/null 2>&1 && DNS_OK=true
DEFAULT_IFACE="$(ip route | awk '/default/ {print $5; exit}')"

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "default_interface": "${DEFAULT_IFACE:-unknown}",
  "default_gateway": "${GATEWAY:-unknown}",
  "target": "$TARGET",
  "target_reachable": $PING_OK,
  "dns_name": "$DNS_NAME",
  "dns_resolution_success": $DNS_OK
}
EOF

printf '\nNetwork diagnostics completed. Output: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
