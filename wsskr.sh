#!/usr/bin/env bash
# Conservative VLESS + TLS + WebSocket TCP tuning for Ubuntu 22.04/24.04 and Debian.
# No firewall/NIC changes, service restarts, or automatic swap allocation.
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
command -v sysctl >/dev/null || { echo 'sysctl is required' >&2; exit 1; }
RAM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
if (( RAM_MB <= 1500 )); then BUFFER=4194304; NOFILE=65536
elif (( RAM_MB <= 4500 )); then BUFFER=8388608; NOFILE=65536
else BUFFER=16777216; NOFILE=131072; fi
FILE=/etc/sysctl.d/90-vless-ws.conf
mkdir -p /etc/sysctl.d
if [[ -f $FILE ]]; then cp -a "$FILE" "${FILE}.bak.$(date +%Y%m%d-%H%M%S)"; fi
# Avoid conflicting settings from an earlier version of this script.
if [[ -f /etc/sysctl.d/99-xray.conf ]]; then
  echo 'WARNING: /etc/sysctl.d/99-xray.conf exists and may override these settings.'
  echo 'Review/remove conflicting entries in that file before continuing.'
  exit 1
fi
cat > "$FILE" <<CONF
# VLESS TLS WebSocket: conservative TCP tuning
fs.file-max = 1048576
net.core.somaxconn = 4096
net.core.rmem_max = ${BUFFER}
net.core.wmem_max = ${BUFFER}
net.ipv4.tcp_rmem = 4096 131072 ${BUFFER}
net.ipv4.tcp_wmem = 4096 131072 ${BUFFER}
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.ip_local_port_range = 10240 65535
CONF
if modprobe tcp_bbr 2>/dev/null && sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
  cat >> "$FILE" <<'CONF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
CONF
  mkdir -p /etc/modules-load.d
  printf 'tcp_bbr\n' > /etc/modules-load.d/90-vless-ws.conf
else
  echo 'BBR unavailable; preserving existing congestion control.'
fi
# Apply only our file; avoid applying unrelated system-wide configurations.
sysctl -p "$FILE"
# Configure whichever service actually hosts Xray, without restarting it.
for SERVICE in x-ui.service xray.service; do
  if systemctl list-unit-files "$SERVICE" --no-legend 2>/dev/null | grep -q "^${SERVICE}[[:space:]]"; then
    DIR="/etc/systemd/system/${SERVICE}.d"
    mkdir -p "$DIR"
    cat > "$DIR/90-vless-ws.conf" <<CONF
[Service]
LimitNOFILE=${NOFILE}
CONF
    echo "Configured ${SERVICE}: LimitNOFILE=${NOFILE} (effective on next restart)"
  fi
done
systemctl daemon-reload
printf '\nCompleted. RAM: %s MB, max TCP buffer: %s bytes\n' "$RAM_MB" "$BUFFER"
printf 'BBR: %s | qdisc: %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control)" "$(sysctl -n net.core.default_qdisc)"
printf 'No firewall, NIC, swap or running services were changed.\n'
