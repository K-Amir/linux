#!/bin/bash
# Enhanced Xray/V2Ray
# Supports Ubuntu 22.04-24.04

# Exit on error, undefined variable, or failure in a pipeline.
set -euo pipefail

# Color definitions for output
GREEN='\033[0;32m'
NC='\033[0m'

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

echo -e "${GREEN}Starting optimized Xray/V2Ray configuration for 1GB RAM VPS with Wi-Fi/Windows fixes...${NC}"

########################################
# 1. Detect the Default Network Interface
########################################
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${GREEN}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

# Verify the interface exists
if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo "Error: Network interface '$DEFAULT_NIC' not found"
    exit 1
fi

########################################
# 2. Install Essential Packages
########################################
# This script is targeted for Ubuntu/Debian
echo -e "${GREEN}Updating package repositories and installing essential packages...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance htop iftop iptables-persistent

########################################
# 3. Setup Swap (4GB)
########################################
# Check if any swap is active; if not, create a 4GB swap file.
if ! swapon --show | grep -q '^/swapfile'; then
    echo -e "${GREEN}No active swap file found. Creating a 4GB swap file...${NC}"
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Ensure swap is mounted on reboot
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    # Optimize swap behavior
    echo 10 > /proc/sys/vm/swappiness
    echo "vm.swappiness = 10" > /etc/sysctl.d/99-swap.conf
else
    echo -e "${GREEN}Swap is already active. Skipping swap file creation.${NC}"
fi

########################################
# 4. Backup Existing sysctl Configuration
########################################
if [[ -f /etc/sysctl.conf ]]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup
fi

########################################
# 5. Apply Memory-Optimized sysctl Settings
########################################
# This file is overwritten each time the script is run.
echo -e "${GREEN}Applying optimized sysctl settings with Wi-Fi/Windows fixes...${NC}"
cat > /etc/sysctl.d/99-xray.conf << 'EOF'
# Optimized settings for VLESS+Reality under low-memory conditions

# Ensure IP forwarding is enabled (critical for tunneling)
net.ipv4.ip_forward = 1

# Increase file descriptors and inotify limits
fs.file-max = 65535
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 32768

# TCP and network performance optimizations
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 8388608
net.ipv4.tcp_wmem = 4096 1048576 8388608
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# Real-time application optimizations
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_thin_dupack = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0

# XTLS Vision Flow optimizations - MODIFIED for compatibility
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 2
# TCP Fast Open DISABLED - causes issues with ~5% of routers
net.ipv4.tcp_fastopen = 0
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
# Modified for more forgiving behavior on unstable networks
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 10
net.ipv4.ip_local_port_range = 1024 65535

# MORE AGGRESSIVE TCP keepalive for NAT traversal
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# Connection tracking optimizations (Less aggressive timeouts)
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# ECN DISABLED - causes issues with some routers
net.ipv4.tcp_ecn = 0

# Virtual memory tuning (Less aggressive)
vm.swappiness = 5
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 16384
vm.dirty_ratio = 20
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory limits and timeouts
net.ipv4.tcp_mem = 196608 393216 786432
net.ipv4.tcp_max_tw_buckets = 131072
# Increased fin_timeout for unstable connections
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_moderate_rcvbuf = 1

# High-speed and low-latency tweaks
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1

net.ipv4.tcp_tw_reuse = 1 # Added for potentially faster socket reuse
net.ipv4.tcp_frto = 1 # Added for better loss recovery

# Fragmentation Settings
net.ipv4.ipfrag_high_thresh = 4194304 # Added, increased memory for IP fragments

# IPv6 settings (enable if needed)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

# Apply the sysctl settings
sysctl --system

########################################
# 6. Optimize Network Interface Settings
########################################
echo -e "${GREEN}Optimizing network interface settings on '$DEFAULT_NIC'...${NC}"

# Enable offloading features
ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Set ring buffer sizes
ethtool -G "$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null || true

# Adjust interrupt coalescence (tweak values as needed)
# Revert to adaptive coalescing to reduce CPU load
# ethtool -C "$DEFAULT_NIC" adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null || true

# Set transmit queue length - REDUCED TO PREVENT BUFFERBLOAT
ip link set dev "$DEFAULT_NIC" txqueuelen 500 2>/dev/null || true

########################################
# 7. Set System Limits for Xray/V2Ray
########################################
echo -e "${GREEN}Applying system limits for Xray/V2Ray...${NC}"
cat > /etc/security/limits.d/99-xray.conf << 'EOF'
* soft     nproc          32768
* hard     nproc          32768
* soft     nofile         32768
* hard     nofile         32768
root soft     nproc          32768
root hard     nproc          32768
root soft     nofile         32768
root hard     nofile         32768
EOF

########################################
# 8. Apply TCP MSS Clamping (Critical for Windows clients)
########################################
echo -e "${GREEN}Applying TCP MSS clamping for Windows client compatibility...${NC}"
# Clear any existing rules in the FORWARD chain
# 1. Only insert the MSS-clamp rules if they aren't there yet
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null \
  || iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360

# 2. Persist IPv6 MSS clamp (if you keep IPv6 enabled)
ip6tables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null \
   || ip6tables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
netfilter-persistent save


########################################
# 9. Load and Persist BBR Congestion Control
########################################
echo -e "${GREEN}Ensuring BBR congestion control is loaded...${NC}"
# Check if BBR is active; note: if built into the kernel, modprobe may not be needed.
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    modprobe tcp_bbr || true
    # Persist the module on boot
    if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi
fi

########################################
# 10. Make txqueuelen Setting Persistent
########################################
echo -e "${GREEN}Making txqueuelen setting persistent...${NC}"
cat > /etc/systemd/system/set-txqueuelen.service << EOF
[Unit]
Description=Set txqueuelen on network interfaces
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip link set dev \$(ip route get 1.1.1.1 | awk "/dev/ {print \\\$5; exit}") txqueuelen 500'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable set-txqueuelen.service
systemctl start set-txqueuelen.service

########################################
# 11. Set CPU Frequency Scaling to "Performance"
########################################
echo -e "${GREEN}Setting CPU scaling governor to 'performance' (if supported)...${NC}"
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu_gov" 2>/dev/null || true
    done
fi

########################################
# Final Message
########################################
echo -e "${GREEN}Optimization complete with Wi-Fi/Windows compatibility fixes!${NC}"
echo -e "${GREEN}Key fixes implemented:${NC}"
echo "1. TCP MSS Clamping to 1360 bytes (fixes Windows MTU issues)"
echo "2. Disabled TCP Fast Open and ECN (problematic on ~5% of routers)"
echo "3. More aggressive TCP keepalives (60s instead of 300s)"
echo "4. Reduced txqueuelen to 500 (reduces bufferbloat)"
echo "5. IP forwarding explicitly enabled"
echo "6. More forgiving TCP retry and timeout parameters"
echo "7. IP TABLES "
echo iptables -t mangle -L FORWARD -v -n | grep TCPMSS
echo "7. IP TABLES V6"
echo ip6tables -t mangle -L FORWARD -v -n | grep TCPMSS
echo -e "${GREEN}Most settings have been applied immediately, though a reboot is recommended for full effect.${NC}"
