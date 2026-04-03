#!/bin/bash
# Optimized Xray/V2Ray VLESS+Reality Configuration Script
# Supports Ubuntu 22.04–24.04 | Auto-detects RAM (1GB–8GB+)
# Designed for censored/DPI-heavy environments
# Date: 2025-02-01

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

########################################
# 0. Detect RAM and Set Scaling Profile
########################################
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))

echo -e "${GREEN}Detected RAM: ${TOTAL_RAM_MB}MB${NC}"

# --- Swap size (ratio decreases as RAM grows) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    # 1GB RAM -> 4GB swap
    SWAP_SIZE="4G"
    SWAP_BS_COUNT=4096
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    # 2GB RAM -> 4GB swap
    SWAP_SIZE="4G"
    SWAP_BS_COUNT=4096
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    # 4GB RAM -> 2GB swap
    SWAP_SIZE="2G"
    SWAP_BS_COUNT=2048
else
    # 8GB+ RAM -> 1GB swap (safety net only)
    SWAP_SIZE="1G"
    SWAP_BS_COUNT=1024
fi

# --- Conntrack max (scales with RAM) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    CONNTRACK_MAX=131072
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    CONNTRACK_MAX=196608
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    CONNTRACK_MAX=262144
else
    CONNTRACK_MAX=524288
fi

# --- TCP memory (in 4KB pages) ---
# Format: min pressure max
# Over-provisioned intentionally: kernel won't allocate more than
# available RAM, but high thresholds prevent premature throttling
# which causes user-visible slowdowns under load.
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    TCP_MEM_MIN=196608      # ~768MB
    TCP_MEM_PRESSURE=393216 # ~1.5GB
    TCP_MEM_MAX=786432      # ~3GB
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    TCP_MEM_MIN=262144      # ~1GB
    TCP_MEM_PRESSURE=524288 # ~2GB
    TCP_MEM_MAX=1048576     # ~4GB
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    TCP_MEM_MIN=524288      # ~2GB
    TCP_MEM_PRESSURE=786432 # ~3GB
    TCP_MEM_MAX=1572864     # ~6GB
else
    TCP_MEM_MIN=786432      # ~3GB
    TCP_MEM_PRESSURE=1048576 # ~4GB
    TCP_MEM_MAX=2097152     # ~8GB
fi

# --- vm.min_free_kbytes (scales with RAM, capped) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MIN_FREE_KB=16384
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MIN_FREE_KB=24576
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    MIN_FREE_KB=32768
else
    MIN_FREE_KB=65536
fi

# --- Max orphans (scales with RAM) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_ORPHANS=16384
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_ORPHANS=32768
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    MAX_ORPHANS=65536
else
    MAX_ORPHANS=131072
fi

# --- Buffer sizes (scale max for larger RAM) ---
if [[ $TOTAL_RAM_MB -le 2500 ]]; then
    RMEM_MAX=8388608      # 8MB
    WMEM_MAX=8388608
    TCP_RMEM_MAX=8388608
    TCP_WMEM_MAX=8388608
else
    RMEM_MAX=16777216      # 16MB
    WMEM_MAX=16777216
    TCP_RMEM_MAX=16777216
    TCP_WMEM_MAX=16777216
fi

# --- File descriptor limits (scale with RAM) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    FILE_MAX=65535
    ULIMIT_NOFILE=32768
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    FILE_MAX=131072
    ULIMIT_NOFILE=65536
else
    FILE_MAX=262144
    ULIMIT_NOFILE=131072
fi

# --- Max TW buckets ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_TW_BUCKETS=65536
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_TW_BUCKETS=131072
else
    MAX_TW_BUCKETS=262144
fi

# --- Max SYN backlog ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_SYN_BACKLOG=16384
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_SYN_BACKLOG=32768
else
    MAX_SYN_BACKLOG=65536
fi

echo -e "${GREEN}RAM Profile: ${TOTAL_RAM_MB}MB | Swap: ${SWAP_SIZE} | Conntrack: ${CONNTRACK_MAX} | TCP mem: ${TCP_MEM_MIN} ${TCP_MEM_PRESSURE} ${TCP_MEM_MAX}${NC}"

########################################
# 1. Detect the Default Network Interface
########################################
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${YELLOW}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo "Error: Network interface '$DEFAULT_NIC' not found"
    exit 1
fi
echo -e "${GREEN}Network interface: ${DEFAULT_NIC}${NC}"

########################################
# 2. Install Essential Packages
########################################
echo -e "${GREEN}Updating packages and installing essentials...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance htop iftop

########################################
# 3. Setup Swap (RAM-aware)
########################################
if ! swapon --show | grep -q '^/swapfile'; then
    echo -e "${GREEN}Creating ${SWAP_SIZE} swap file...${NC}"
    fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_BS_COUNT"
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
else
    echo -e "${GREEN}Swap already active. Skipping.${NC}"
fi

########################################
# 4. Backup Existing sysctl Configuration
########################################
if [[ -f /etc/sysctl.conf ]]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup
fi

# Remove any conflicting swap sysctl from earlier runs
rm -f /etc/sysctl.d/99-swap.conf

########################################
# 5. Apply RAM-Aware sysctl Settings
########################################
echo -e "${GREEN}Applying optimized sysctl settings...${NC}"
cat > /etc/sysctl.d/99-xray.conf << EOF
# Auto-generated for ${TOTAL_RAM_MB}MB RAM
# Optimized for VLESS+Reality in censored environments

# File descriptors and inotify
fs.file-max = ${FILE_MAX}
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 32768

# Core network buffers (RAM-scaled)
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = ${RMEM_MAX}
net.core.wmem_max = ${WMEM_MAX}
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 ${TCP_RMEM_MAX}
net.ipv4.tcp_wmem = 4096 1048576 ${TCP_WMEM_MAX}
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Latency and responsiveness
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_thin_dupack = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0

# XTLS Vision Flow optimizations
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 2
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8
net.ipv4.ip_local_port_range = 1024 65535

# TCP keepalive (tolerant for mobile/unstable clients)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 9

# Connection tracking (RAM-scaled)
net.netfilter.nf_conntrack_max = ${CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 0

# Virtual memory (single source of truth for swappiness)
vm.swappiness = 5
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = ${MIN_FREE_KB}
vm.dirty_ratio = 20
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory and connection limits (RAM-scaled)
net.ipv4.tcp_mem = ${TCP_MEM_MIN} ${TCP_MEM_PRESSURE} ${TCP_MEM_MAX}
net.ipv4.tcp_max_tw_buckets = ${MAX_TW_BUCKETS}
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = ${MAX_SYN_BACKLOG}
net.ipv4.tcp_max_orphans = ${MAX_ORPHANS}
net.ipv4.tcp_moderate_rcvbuf = 1

# Performance tweaks
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_frto = 1

# Fragmentation
net.ipv4.ipfrag_high_thresh = 4194304

# Anti-probing hardening (censored environments)
# Prevents censors from ping-probing your VPS after detecting proxy traffic
net.ipv4.icmp_echo_ignore_all = 1
net.ipv6.icmp.echo_ignore_all = 1

# IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

sysctl --system

########################################
# 6. Optimize Network Interface Settings
########################################
echo -e "${GREEN}Optimizing network interface '${DEFAULT_NIC}'...${NC}"

ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true
ethtool -G "$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null || true
ip link set dev "$DEFAULT_NIC" txqueuelen 1000 2>/dev/null || true

########################################
# 7. Set System Limits for Xray/V2Ray
########################################
echo -e "${GREEN}Applying system limits...${NC}"
cat > /etc/security/limits.d/99-xray.conf << EOF
* soft     nproc          ${ULIMIT_NOFILE}
* hard     nproc          ${ULIMIT_NOFILE}
* soft     nofile         ${ULIMIT_NOFILE}
* hard     nofile         ${ULIMIT_NOFILE}
root soft     nproc          ${ULIMIT_NOFILE}
root hard     nproc          ${ULIMIT_NOFILE}
root soft     nofile         ${ULIMIT_NOFILE}
root hard     nofile         ${ULIMIT_NOFILE}
EOF

########################################
# 8. Systemd Override for 3x-ui / Xray
########################################
echo -e "${GREEN}Creating systemd override for x-ui service...${NC}"
mkdir -p /etc/systemd/system/x-ui.service.d/
cat > /etc/systemd/system/x-ui.service.d/override.conf << EOF
[Service]
LimitNOFILE=${ULIMIT_NOFILE}
LimitNPROC=${ULIMIT_NOFILE}
Restart=always
RestartSec=3
EOF

# Also override xray service if it exists separately
if systemctl list-unit-files | grep -q '^xray.service'; then
    mkdir -p /etc/systemd/system/xray.service.d/
    cat > /etc/systemd/system/xray.service.d/override.conf << EOF
[Service]
LimitNOFILE=${ULIMIT_NOFILE}
LimitNPROC=${ULIMIT_NOFILE}
Restart=always
RestartSec=3
EOF
fi

systemctl daemon-reload

# Restart x-ui if it's already running
if systemctl is-active --quiet x-ui 2>/dev/null; then
    echo -e "${GREEN}Restarting x-ui service...${NC}"
    systemctl restart x-ui
fi

########################################
# 9. Load and Persist BBR Congestion Control
########################################
echo -e "${GREEN}Ensuring BBR is loaded...${NC}"
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    modprobe tcp_bbr || true
    if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi
fi

########################################
# 10. CPU Frequency Scaling
########################################
echo -e "${GREEN}Setting CPU governor to 'performance' (if supported)...${NC}"
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu_gov" 2>/dev/null || true
    done
fi

systemctl daemon-reload

########################################
# Summary
########################################
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Optimization Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  RAM:           ${TOTAL_RAM_MB}MB${NC}"
echo -e "${GREEN}  Swap:          ${SWAP_SIZE}${NC}"
echo -e "${GREEN}  Conntrack max: ${CONNTRACK_MAX}${NC}"
echo -e "${GREEN}  TCP mem:       ${TCP_MEM_MIN} / ${TCP_MEM_PRESSURE} / ${TCP_MEM_MAX} pages${NC}"
echo -e "${GREEN}  File max:      ${FILE_MAX}${NC}"
echo -e "${GREEN}  Ulimit nofile: ${ULIMIT_NOFILE}${NC}"
echo -e "${GREEN}  Interface:     ${DEFAULT_NIC} (txqueuelen 1000)${NC}"
echo -e "${GREEN}  Congestion:    BBR + fq${NC}"
echo -e "${GREEN}  ECN:           disabled (censored env)${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}  A reboot is recommended for full effect.${NC}"
echo ""
