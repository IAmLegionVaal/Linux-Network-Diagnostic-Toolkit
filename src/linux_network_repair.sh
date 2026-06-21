#!/usr/bin/env bash
set -u

DO_REPAIR=false
INTERFACE=""
RENEW=false
CYCLE=false
FLUSH_DNS=false
RESTART_NETWORK=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: linux_network_repair.sh [options]

  --repair               Restart the active network-management service.
  --interface IFACE      Interface for renew or cycle actions.
  --renew-dhcp           Renew DHCP on the selected interface.
  --cycle-interface      Bring the selected interface down and up through its manager.
  --flush-dns            Flush resolver caches and restart the resolver service.
  --dry-run              Show commands without changing the system.
  --yes                  Skip confirmation prompts.
  --output DIR           Save logs and verification output in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair) DO_REPAIR=true; RESTART_NETWORK=true; shift ;;
    --interface) INTERFACE="${2:-}"; shift 2 ;;
    --renew-dhcp) DO_REPAIR=true; RENEW=true; shift ;;
    --cycle-interface) DO_REPAIR=true; CYCLE=true; shift ;;
    --flush-dns) DO_REPAIR=true; FLUSH_DNS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

$DO_REPAIR || { echo "Choose at least one repair action." >&2; exit 2; }
if { $RENEW || $CYCLE; } && [ -z "$INTERFACE" ]; then echo "--interface is required." >&2; exit 2; fi
if [ -n "$INTERFACE" ]; then ip link show "$INTERFACE" >/dev/null 2>&1 || { echo "Interface not found: $INTERFACE" >&2; exit 2; }; fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./linux-network-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
manager() {
  systemctl is-active --quiet NetworkManager 2>/dev/null && { echo NetworkManager; return; }
  systemctl is-active --quiet systemd-networkd 2>/dev/null && { echo systemd-networkd; return; }
  systemctl is-active --quiet networking 2>/dev/null && { echo networking; return; }
  echo none
}
verify() {
  {
    echo "Collected: $(date -Is)"
    ip -br link
    ip -br addr
    ip route
    echo
    resolvectl status 2>/dev/null || cat /etc/resolv.conf
    echo
    ping -c 2 -W 2 1.1.1.1 2>&1 || true
    getent hosts example.com 2>&1 || true
    if [ -n "$INTERFACE" ]; then echo; ip -s link show "$INTERFACE"; fi
  } > "$VERIFY"
}

verify
confirm "Apply the selected network repairs? Active sessions may be interrupted." || { log "Repair cancelled."; exit 10; }
MANAGER=$(manager)

if $RESTART_NETWORK; then
  case "$MANAGER" in
    NetworkManager) run_root "Restarting NetworkManager" systemctl restart NetworkManager || true ;;
    systemd-networkd) run_root "Restarting systemd-networkd" systemctl restart systemd-networkd || true ;;
    networking) run_root "Restarting networking service" systemctl restart networking || true ;;
    none) FAILURES=$((FAILURES + 1)); log "WARNING: supported network manager not detected." ;;
  esac
fi

if $FLUSH_DNS; then
  command -v resolvectl >/dev/null 2>&1 && run_root "Flushing systemd-resolved caches" resolvectl flush-caches || true
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then run_root "Restarting systemd-resolved" systemctl restart systemd-resolved || true; fi
  if systemctl is-active --quiet dnsmasq 2>/dev/null; then run_root "Restarting dnsmasq" systemctl restart dnsmasq || true; fi
fi

if $RENEW; then
  case "$MANAGER" in
    NetworkManager) run_root "Reapplying NetworkManager configuration to $INTERFACE" nmcli device reapply "$INTERFACE" || true ;;
    systemd-networkd) run_root "Renewing DHCP on $INTERFACE" networkctl renew "$INTERFACE" || true ;;
    *)
      if command -v dhclient >/dev/null 2>&1; then run_root "Releasing DHCP on $INTERFACE" dhclient -r "$INTERFACE" || true; run_root "Renewing DHCP on $INTERFACE" dhclient "$INTERFACE" || true; else FAILURES=$((FAILURES + 1)); log "WARNING: no DHCP renewal tool found."; fi
      ;;
  esac
fi

if $CYCLE; then
  case "$MANAGER" in
    NetworkManager) run_root "Disconnecting $INTERFACE" nmcli device disconnect "$INTERFACE" || true; $DRY_RUN || sleep 2; run_root "Connecting $INTERFACE" nmcli device connect "$INTERFACE" || true ;;
    systemd-networkd) run_root "Reconfiguring $INTERFACE" networkctl reconfigure "$INTERFACE" || true ;;
    *) run_root "Bringing $INTERFACE down" ip link set "$INTERFACE" down || true; $DRY_RUN || sleep 2; run_root "Bringing $INTERFACE up" ip link set "$INTERFACE" up || true ;;
  esac
fi

$DRY_RUN || sleep 4
verify
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
