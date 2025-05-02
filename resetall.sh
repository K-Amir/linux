#!/bin/bash
# Script to reset all changes made by the V2 optimization script
# Run as root

echo "Resetting all V2 script optimizations..."

# 1. Reset iptables rules
echo "Resetting iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F
iptables -X
iptables -t nat -X
iptables -t mangle -X
iptables -t raw -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Also reset IPv6 tables
ip6tables -F
ip6tables -t nat -F
ip6tables -t mangle -F
ip6tables -t raw -F
ip6tables -X
ip6tables -t nat -X
ip6tables -t mangle -X
ip6tables -t raw -X
ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT

# 2. Reset sysctl parameters to defaults
echo "Resetting sysctl parameters..."
# Reset TCP settings
sysctl -w net.ipv4.tcp_fastopen=1
sysctl -w net.ipv4.tcp_ecn=2
sysctl -w net.ipv4.tcp_keepalive_time=7200
sysctl -w net.ipv4.tcp_keepalive_intvl=75
sysctl -w net.ipv4.tcp_keepalive_probes=9
sysctl -w net.ipv4.tcp_fin_timeout=60
sysctl -w net.ipv4.tcp_retries2=15
sysctl -w net.ipv4.tcp_rmem='4096 87380 6291456'
sysctl -w net.ipv4.tcp_wmem='4096 16384 4194304'
sysctl -w net.core.rmem_max=212992
sysctl -w net.core.wmem_max=212992
sysctl -w net.core.netdev_max_backlog=1000
sysctl -w net.core.somaxconn=128
sysctl -w net.ipv4.tcp_notsent_lowat=4294967295
sysctl -w net.ipv4.tcp_mtu_probing=0
sysctl -w net.ipv4.tcp_syn_retries=6
sysctl -w net.ipv4.tcp_synack_retries=5
sysctl -w net.ipv4.tcp_retries1=3
sysctl -w net.ipv4.tcp_retries2=15

# Reset VM settings
sysctl -w vm.swappiness=60
sysctl -w vm.vfs_cache_pressure=100
sysctl -w vm.dirty_ratio=30
sysctl -w vm.dirty_background_ratio=10
sysctl -w vm.dirty_expire_centisecs=3000
sysctl -w vm.dirty_writeback_centisecs=500
sysctl -w vm.page-cluster=3

# Reset conntrack settings
sysctl -w net.netfilter.nf_conntrack_max=65536
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000

# Reset congestion control
sysctl -w net.core.default_qdisc=pfifo_fast
sysctl -w net.ipv4.tcp_congestion_control=cubic

# 3. Remove the custom systemd service
echo "Removing custom systemd service..."
systemctl stop set-txqueuelen.service 2>/dev/null
systemctl disable set-txqueuelen.service 2>/dev/null
rm -f /etc/systemd/system/set-txqueuelen.service
systemctl daemon-reload

# 4. Reset network interface settings
echo "Resetting network interface settings..."
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -n "$DEFAULT_NIC" ]]; then
  # Reset txqueuelen to default (1000 is typical default)
  ip link set dev "$DEFAULT_NIC" txqueuelen 1000
  
  # Reset offloading to default (usually on for most features)
  ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true
fi

# 5. Remove custom sysctl configurations
echo "Removing custom sysctl configurations..."
rm -f /etc/sysctl.d/99-xray.conf
rm -f /etc/sysctl.d/99-swap.conf

# 6. Reset CPU governor (if applicable)
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
  echo "Resetting CPU governor to ondemand..."
  for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo "ondemand" > "$cpu_gov" 2>/dev/null || true
  done
fi

# 7. Remove system limits
echo "Removing system limits for Xray/V2Ray..."
rm -f /etc/security/limits.d/99-xray.conf

# 8. Apply system changes
echo "Applying changes..."
sysctl --system

echo "Reset complete. It's recommended to reboot the system to ensure all changes take effect."
echo "You can reboot by running: sudo reboot"
