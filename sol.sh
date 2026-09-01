#!/bin/bash
# Optimized Xray/V2Ray VLESS+Reality + Hysteria2 Configuration Script
# Supports Ubuntu 22.04–24.04 | Auto-detects RAM (1GB–8GB+)
# Designed for censored/DPI-heavy environments with UDP optimization
# Date: 2026-09-01
# Optimized for: 2000-6000 users across 125 nodes (~16-48 users per node)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logging
LOG_FILE="/var/log/optimizer_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  VPS Optimizer for VLESS+Reality + Hysteria2${NC}"
echo -e "${GREEN}  High-capacity: Up to 2000 users per node${NC}"
echo -e "${GREEN}========================================${NC}"

########################################
# 0. Detect RAM and Set Scaling Profile
########################################
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
CPU_CORES=$(nproc)

echo -e "${GREEN}Detected: ${TOTAL_RAM_MB}MB RAM, ${CPU_CORES} CPU cores${NC}"

# --- Swap size (ratio decreases as RAM grows) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    SWAP_SIZE="4G"
    SWAP_BS_COUNT=4096
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    SWAP_SIZE="4G"
    SWAP_BS_COUNT=4096
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    SWAP_SIZE="2G"
    SWAP_BS_COUNT=2048
else
    SWAP_SIZE="1G"
    SWAP_BS_COUNT=1024
fi

# --- Conntrack max (optimized for up to 2000 users/node - maximum headroom) ---
# Each conntrack entry = ~350 bytes RAM
# 2000 users @ 50% active × 150 conn/user = 150K base + overhead = 300K needed
# Setting 2-3x higher for safety - conntrack limit will NOT cause shutdown
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    CONNTRACK_MAX=1048576     # 1M (~350MB RAM) - absolute maximum for 1GB
    LOCAL_PORT_MIN=10000
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    CONNTRACK_MAX=2097152     # 2M (~700MB RAM) - high capacity
    LOCAL_PORT_MIN=5000
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    CONNTRACK_MAX=3145728     # 3M (~1GB RAM) - very high capacity
    LOCAL_PORT_MIN=5000
else
    CONNTRACK_MAX=4194304     # 4M (~1.4GB RAM) - extreme capacity
    LOCAL_PORT_MIN=1024
fi

# --- TCP memory (in 4KB pages) ---
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

# --- Max orphans (scales with RAM, increased for 2000 users) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_ORPHANS=131072     # 128K for heavy load
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_ORPHANS=262144     # 256K
elif [[ $TOTAL_RAM_MB -le 4500 ]]; then
    MAX_ORPHANS=524288     # 512K
else
    MAX_ORPHANS=1048576    # 1M
fi

# --- Buffer sizes (larger for UDP/Hysteria2) ---
if [[ $TOTAL_RAM_MB -le 2500 ]]; then
    RMEM_MAX=16777216      # 16MB (increased for UDP)
    WMEM_MAX=16777216
    TCP_RMEM_MAX=8388608   # 8MB for TCP
    TCP_WMEM_MAX=8388608
else
    RMEM_MAX=26214400      # 25MB (Hysteria2 needs large UDP buffers)
    WMEM_MAX=26214400
    TCP_RMEM_MAX=16777216  # 16MB for TCP
    TCP_WMEM_MAX=16777216
fi

# --- File descriptor limits (scale with RAM, optimized for 2000 users) ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    FILE_MAX=524288        # 512K - aggressive for 1GB
    ULIMIT_NOFILE=262144   # 256K
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    FILE_MAX=1048576       # 1M - high capacity
    ULIMIT_NOFILE=524288   # 512K
else
    FILE_MAX=2097152       # 2M - maximum capacity
    ULIMIT_NOFILE=1048576  # 1M
fi

# --- Max TW buckets ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_TW_BUCKETS=262144  # 256K
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_TW_BUCKETS=524288  # 512K
else
    MAX_TW_BUCKETS=1048576 # 1M
fi

# --- Max SYN backlog ---
if [[ $TOTAL_RAM_MB -le 1200 ]]; then
    MAX_SYN_BACKLOG=16384
elif [[ $TOTAL_RAM_MB -le 2500 ]]; then
    MAX_SYN_BACKLOG=32768
else
    MAX_SYN_BACKLOG=65536
fi

echo -e "${GREEN}Profile: ${TOTAL_RAM_MB}MB | ${CPU_CORES}C | Swap: ${SWAP_SIZE} | Conntrack: ${CONNTRACK_MAX}${NC}"
echo -e "${GREEN}TCP mem: ${TCP_MEM_MIN}/${TCP_MEM_PRESSURE}/${TCP_MEM_MAX} pages | Ports: ${LOCAL_PORT_MIN}-65535${NC}"

########################################
# 1. Detect the Default Network Interface
########################################
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${YELLOW}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo -e "${RED}Error: Network interface '$DEFAULT_NIC' not found${NC}"
    exit 1
fi
echo -e "${GREEN}Network interface: ${DEFAULT_NIC}${NC}"

########################################
# 2. Install Essential Packages
########################################
echo -e "${GREEN}Updating packages and installing essentials...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance htop iftop net-tools

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
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%s)
fi

# Remove any conflicting configs from earlier runs
rm -f /etc/sysctl.d/99-swap.conf

########################################
# 5. Apply RAM-Aware sysctl Settings
########################################
echo -e "${GREEN}Applying optimized sysctl settings for VLESS+Reality + Hysteria2...${NC}"
cat > /etc/sysctl.d/99-xray.conf << EOF
# Auto-generated for ${TOTAL_RAM_MB}MB RAM, ${CPU_CORES} CPU cores
# Optimized for VLESS+Reality + Hysteria2 in censored environments
# Load profile: 16-48 users/node across 125 nodes

# ==========================================
# File Descriptors & Inotify
# ==========================================
fs.file-max = ${FILE_MAX}
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 65536

# ==========================================
# Core Network Buffers (RAM-scaled, UDP optimized)
# ==========================================
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 16384
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = ${RMEM_MAX}
net.core.wmem_max = ${WMEM_MAX}
net.core.optmem_max = 65536

# TCP buffers
net.ipv4.tcp_rmem = 4096 1048576 ${TCP_RMEM_MAX}
net.ipv4.tcp_wmem = 4096 1048576 ${TCP_WMEM_MAX}

# UDP buffers (CRITICAL for Hysteria2)
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = ${TCP_MEM_MIN} ${TCP_MEM_PRESSURE} ${TCP_MEM_MAX}

# ==========================================
# TCP Performance & Latency
# ==========================================
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_thin_dupack = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 2

# Fast recovery
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fastopen_blackhole_timeout_sec = 3600
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# Enable critical TCP features
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8

# Port range for ephemeral connections
net.ipv4.ip_local_port_range = ${LOCAL_PORT_MIN} 65535

# ==========================================
# TCP Keepalive (tolerant for mobile/unstable)
# ==========================================
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 9

# ==========================================
# Connection Tracking (RAM-scaled, UDP aware)
# ==========================================
net.netfilter.nf_conntrack_max = ${CONNTRACK_MAX}
net.netfilter.nf_conntrack_buckets = $((CONNTRACK_MAX / 4))
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# UDP conntrack timeouts (Hysteria2)
net.netfilter.nf_conntrack_udp_timeout = 90
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.netfilter.nf_conntrack_generic_timeout = 60

# Disable conntrack helpers (security)
net.netfilter.nf_conntrack_helper = 0

# ==========================================
# BBR Congestion Control
# ==========================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 0

# ==========================================
# Virtual Memory (single source of truth)
# ==========================================
vm.swappiness = 5
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = ${MIN_FREE_KB}
vm.dirty_ratio = 20
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# Memory overcommit (allow for burst load)
vm.overcommit_memory = 1
vm.overcommit_ratio = 100

# ==========================================
# TCP Connection Limits (RAM-scaled)
# ==========================================
net.ipv4.tcp_mem = ${TCP_MEM_MIN} ${TCP_MEM_PRESSURE} ${TCP_MEM_MAX}
net.ipv4.tcp_max_tw_buckets = ${MAX_TW_BUCKETS}
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = ${MAX_SYN_BACKLOG}
net.ipv4.tcp_max_orphans = ${MAX_ORPHANS}
net.ipv4.tcp_moderate_rcvbuf = 1

# ==========================================
# TCP Performance Tweaks
# ==========================================
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_app_win = 31
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_frto = 2

# ==========================================
# Fragmentation Handling
# ==========================================
net.ipv4.ipfrag_high_thresh = 4194304
net.ipv4.ipfrag_low_thresh = 3145728
net.ipv4.ipfrag_time = 15

# ==========================================
# Security Hardening (Censored Environments)
# ==========================================
# SYN flood protection
net.ipv4.tcp_syncookies = 1

# ICMP (allow for PMTU discovery, block broadcasts)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
# Note: NOT blocking all ICMP - breaks Path MTU Discovery

# Reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Disable redirects (prevents MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ==========================================
# IPv6 Support
# ==========================================
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

# Enable offloading features
ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Try to increase ring buffer sizes
ethtool -G "$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null || {
    echo -e "${YELLOW}Could not set ring buffer to 4096, trying smaller values...${NC}"
    ethtool -G "$DEFAULT_NIC" rx 2048 tx 2048 2>/dev/null || true
}

# Set transmit queue length
ip link set dev "$DEFAULT_NIC" txqueuelen 10000 2>/dev/null || true

# Check and set MTU
MTU=$(ip link show "$DEFAULT_NIC" | grep -oP 'mtu \K[0-9]+')
if [[ $MTU -ge 9000 ]]; then
    echo -e "${GREEN}Jumbo frames detected (MTU=$MTU) - keeping for performance${NC}"
else
    echo -e "${GREEN}Standard MTU: $MTU${NC}"
    ip link set dev "$DEFAULT_NIC" mtu 1500 2>/dev/null || true
fi

########################################
# 7. Multi-Core Optimization (RPS/RFS)
########################################
if [[ $CPU_CORES -ge 2 ]]; then
    echo -e "${GREEN}Configuring RPS/RFS for ${CPU_CORES} CPU cores...${NC}"

    # Calculate CPU mask for all cores
    RPS_MASK=$(printf '%x' $((2**CPU_CORES - 1)))

    # Enable RPS (Receive Packet Steering)
    for rps_file in /sys/class/net/${DEFAULT_NIC}/queues/rx-*/rps_cpus; do
        if [[ -f "$rps_file" ]]; then
            echo "$RPS_MASK" > "$rps_file" 2>/dev/null || true
        fi
    done

    # Enable RFS (Receive Flow Steering)
    echo 65536 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
    for rps_flow in /sys/class/net/${DEFAULT_NIC}/queues/rx-*/rps_flow_cnt; do
        if [[ -f "$rps_flow" ]]; then
            echo 16384 > "$rps_flow" 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}RPS/RFS configured: CPU mask=${RPS_MASK}${NC}"
else
    echo -e "${YELLOW}Single core detected - skipping RPS/RFS${NC}"
fi

########################################
# 8. Set System Limits for Xray/V2Ray
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
# 9. Systemd Override for x-ui / Xray / Hysteria
########################################
echo -e "${GREEN}Creating systemd service overrides...${NC}"

# x-ui service
mkdir -p /etc/systemd/system/x-ui.service.d/
cat > /etc/systemd/system/x-ui.service.d/override.conf << EOF
[Service]
LimitNOFILE=${ULIMIT_NOFILE}
LimitNPROC=${ULIMIT_NOFILE}
Restart=always
RestartSec=3
EOF

# Xray service (if separate)
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

# Hysteria service (if exists)
if systemctl list-unit-files | grep -q 'hysteria'; then
    HYSTERIA_SERVICE=$(systemctl list-unit-files | grep hysteria | head -1 | awk '{print $1}')
    mkdir -p /etc/systemd/system/${HYSTERIA_SERVICE}.d/
    cat > /etc/systemd/system/${HYSTERIA_SERVICE}.d/override.conf << EOF
[Service]
LimitNOFILE=${ULIMIT_NOFILE}
LimitNPROC=${ULIMIT_NOFILE}
Restart=always
RestartSec=3
EOF
    echo -e "${GREEN}Configured ${HYSTERIA_SERVICE}${NC}"
fi

systemctl daemon-reload

# Restart services if running
if systemctl is-active --quiet x-ui 2>/dev/null; then
    echo -e "${GREEN}Restarting x-ui service...${NC}"
    systemctl restart x-ui
fi

########################################
# 10. Load and Persist BBR
########################################
echo -e "${GREEN}Ensuring BBR congestion control is loaded...${NC}"

# Detect kernel version for BBR variant
KERNEL_VERSION=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)

if [[ $KERNEL_VERSION -ge 6 ]] && [[ $KERNEL_MINOR -ge 6 ]]; then
    echo -e "${GREEN}Kernel 6.6+ detected - BBRv3 capabilities available${NC}"
fi

# Load BBR module
modprobe tcp_bbr 2>/dev/null || true

# Persist across reboots
if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

# Verify BBR is active
CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [[ "$CURRENT_CC" == "bbr" ]]; then
    echo -e "${GREEN}BBR active: $(lsmod | grep tcp_bbr)${NC}"
else
    echo -e "${YELLOW}Warning: BBR not active. Current: $CURRENT_CC${NC}"
fi

########################################
# 11. Configure IRQBalance
########################################
echo -e "${GREEN}Configuring IRQBalance for multi-core efficiency...${NC}"
cat > /etc/default/irqbalance << 'EOF'
ENABLED=1
ONESHOT=0
IRQBALANCE_ARGS="--hintpolicy=exact"
EOF

systemctl enable irqbalance 2>/dev/null || true
systemctl restart irqbalance 2>/dev/null || true

########################################
# 12. CPU Frequency Scaling
########################################
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    AVAILABLE_GOVS=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo "")

    if echo "$AVAILABLE_GOVS" | grep -q "performance"; then
        echo -e "${GREEN}Setting CPU governor to 'performance'${NC}"
        for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "performance" > "$cpu_gov" 2>/dev/null || true
        done
    else
        echo -e "${YELLOW}Performance governor not available - using default${NC}"
    fi
else
    echo -e "${YELLOW}No CPU frequency scaling available (VPS/VM)${NC}"
fi

########################################
# 13. Disable Unnecessary Services
########################################
echo -e "${GREEN}Disabling unnecessary services for performance...${NC}"
for service in snapd.service snapd.socket systemd-resolved.service; do
    if systemctl is-enabled "$service" 2>/dev/null | grep -q enabled; then
        systemctl disable "$service" 2>/dev/null || true
        echo -e "${YELLOW}Disabled: $service${NC}"
    fi
done

########################################
# Summary
########################################
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Optimization Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  RAM:              ${TOTAL_RAM_MB}MB${NC}"
echo -e "${GREEN}  CPU Cores:        ${CPU_CORES}${NC}"
echo -e "${GREEN}  Swap:             ${SWAP_SIZE}${NC}"
echo -e "${GREEN}  Conntrack max:    ${CONNTRACK_MAX}${NC}"
echo -e "${GREEN}  TCP mem (pages):  ${TCP_MEM_MIN} / ${TCP_MEM_PRESSURE} / ${TCP_MEM_MAX}${NC}"
echo -e "${GREEN}  UDP mem (pages):  ${TCP_MEM_MIN} / ${TCP_MEM_PRESSURE} / ${TCP_MEM_MAX}${NC}"
echo -e "${GREEN}  File descriptors: ${FILE_MAX}${NC}"
echo -e "${GREEN}  Ulimit nofile:    ${ULIMIT_NOFILE}${NC}"
echo -e "${GREEN}  Interface:        ${DEFAULT_NIC} (txqueuelen 10000)${NC}"
echo -e "${GREEN}  MTU:              ${MTU}${NC}"
echo -e "${GREEN}  Congestion:       BBR (kernel $(uname -r))${NC}"
echo -e "${GREEN}  Ephemeral ports:  ${LOCAL_PORT_MIN}-65535${NC}"
echo -e "${GREEN}  RPS/RFS:          $([ $CPU_CORES -ge 2 ] && echo "Enabled" || echo "N/A (1 core)")${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Protocol Support:${NC}"
echo -e "${GREEN}    - VLESS+Reality (TCP optimized)${NC}"
echo -e "${GREEN}    - Hysteria2 (UDP optimized)${NC}"
echo -e "${GREEN}    - Load: 16-48 users/node (125 nodes)${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}  Log saved: ${LOG_FILE}${NC}"
echo -e "${YELLOW}  Reboot recommended for full effect.${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
