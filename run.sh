#!/bin/bash

#----------------------------------------------------
#  COMPLETE OPTIMIZATION SCRIPT FOR XRAY VLESS+REALITY
#  - Enhanced connection stability
#  - Full system optimization
#  - IRQ and CPU optimizations
#  - Memory management
#----------------------------------------------------

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting complete Xray optimization...${NC}"

#-----------------------------------------------
# 1. Detect default network interface
#-----------------------------------------------
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${GREEN}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

#-----------------------------------------------
# 2. Install essential packages
#-----------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance

#-----------------------------------------------
# 3. Enhanced sysctl configurations
#-----------------------------------------------
cat > /etc/sysctl.d/99-xray-complete.conf << EOF
# System limits
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# TCP optimization for stability and performance
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Enhanced TCP stability settings
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries1 = 5
net.ipv4.tcp_retries2 = 15
net.ipv4.ip_local_port_range = 1024 65535

# Aggressive TCP keepalive for connection persistence
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Extended connection tracking
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 7440
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Memory optimization
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 131072
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-xray-complete.conf

#-----------------------------------------------
# 4. Network interface optimization
#-----------------------------------------------
# Enable offloading features
ethtool -K "${DEFAULT_NIC}" tso on gso on gro on 2>/dev/null || true
# Set ring buffer sizes
ethtool -G "${DEFAULT_NIC}" rx 4096 tx 4096 2>/dev/null || true

#-----------------------------------------------
# 5. System limits for Xray
#-----------------------------------------------
cat > /etc/security/limits.d/99-xray.conf << EOF
* soft     nproc          65535
* hard     nproc          65535
* soft     nofile         1000000
* hard     nofile         1000000
root soft     nproc          65535
root hard     nproc          65535
root soft     nofile         1000000
root hard     nofile         1000000
EOF

#-----------------------------------------------
# 6. Optimize IRQ balance for network card
#-----------------------------------------------
if [ -f /etc/default/irqbalance ]; then
    sed -i 's/#IRQBALANCE_BANNED_CPUS=/IRQBALANCE_BANNED_CPUS=/' /etc/default/irqbalance
    systemctl restart irqbalance
fi

#-----------------------------------------------
# 7. Memory management
#-----------------------------------------------
cat > /etc/cron.hourly/memory-management << 'EOF'
#!/bin/bash
USED=$(free | awk '/^Mem/ {print int($3/$2 * 100)}')
if [ "$USED" -gt 90 ]; then
    sync
    echo 1 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory
fi
EOF
chmod +x /etc/cron.hourly/memory-management

#-----------------------------------------------
# 8. Load and persist BBR
#-----------------------------------------------
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

#-----------------------------------------------
# 9. Network scheduler optimization
#-----------------------------------------------
if [ -f /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_cpus ]; then
    echo 'ff' > /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_cpus
    echo 'ff' > /sys/class/net/${DEFAULT_NIC}/queues/tx-0/xps_cpus
    echo 32768 > /proc/sys/net/core/rps_sock_flow_entries
    echo 32768 > /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_flow_cnt
fi

echo -e "${GREEN}Complete optimization finished!${NC}"
echo -e "${GREEN}Please reboot your system to apply all changes.${NC}"
