#!/bin/bash

#----------------------------------------------------
#  OPTIMIZED SCRIPT FOR XRAY VLESS+REALITY (1GB RAM)
#  - Memory-optimized settings
#  - Swap configuration
#  - Conservative system optimization
#----------------------------------------------------

GREEN='\033[0;32m'
NC='\033[0m'

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo -e "${GREEN}Starting optimized Xray configuration for 1GB RAM VPS...${NC}"

#-----------------------------------------------
# 1. Detect default network interface
#-----------------------------------------------
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${GREEN}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

# Validate network interface
if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo "Error: Network interface $DEFAULT_NIC not found"
    exit 1
fi

#-----------------------------------------------
# 2. Install essential packages
#-----------------------------------------------
if command -v apt-get >/dev/null; then
    # Debian/Ubuntu
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget unzip ethtool haveged irqbalance htop iftop
elif command -v yum >/dev/null; then
    # CentOS/RHEL
    yum update -y
    yum install -y curl wget unzip ethtool haveged irqbalance htop iftop
fi

#-----------------------------------------------
# 3. Setup Swap (4GB)
#-----------------------------------------------
if [ ! -f /swapfile ]; then
    echo -e "${GREEN}Creating 4GB swap file...${NC}"
    dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # Optimize swap settings for better performance
    echo 10 > /proc/sys/vm/swappiness
    echo "vm.swappiness = 10" >> /etc/sysctl.d/99-swap.conf
fi

#-----------------------------------------------
# 4. Backup current sysctl configuration
#-----------------------------------------------
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup
fi

#-----------------------------------------------
# 5. Memory-optimized sysctl configurations
#-----------------------------------------------
cat > /etc/sysctl.d/99-xray-complete.conf << EOF
# System limits - optimized for VLESS
fs.file-max = 65535
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 32768

# TCP optimization for VLESS+REALITY
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

# XTLS Vision Flow optimizations
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_retries1 = 2
net.ipv4.tcp_retries2 = 3
net.ipv4.ip_local_port_range = 1024 65535

# Aggressive keepalive for better responsiveness
net.ipv4.tcp_keepalive_time = 15
net.ipv4.tcp_keepalive_intvl = 3
net.ipv4.tcp_keepalive_probes = 3

# Enhanced connection tracking
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 300
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control optimized for real-time
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 1

# Memory optimization for real-time connections
vm.swappiness = 5
vm.vfs_cache_pressure = 40
vm.min_free_kbytes = 65536
vm.dirty_ratio = 20
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory limits - optimized for real-time
net.ipv4.tcp_mem = 131072 262144 524288
net.ipv4.tcp_max_tw_buckets = 131072
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_moderate_rcvbuf = 1

# High-speed network optimizations
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.route.flush = 1

# IPv6 optimizations (if needed)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-xray-complete.conf

#-----------------------------------------------
# 6. Network interface optimization (enhanced)
#-----------------------------------------------
# Enable optimized network offloading
ethtool -K ${DEFAULT_NIC} tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Optimize ring buffer sizes for high speed
ethtool -G ${DEFAULT_NIC} rx 4096 tx 4096 2>/dev/null || true

# Optimize interrupt coalescence for real-time apps
ethtool -C ${DEFAULT_NIC} adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null || true

# Increase queue length for better performance
ip link set dev ${DEFAULT_NIC} txqueuelen 10000 2>/dev/null || true

#-----------------------------------------------
# 7. System limits for Xray (conservative)
#-----------------------------------------------
cat > /etc/security/limits.d/99-xray.conf << EOF
* soft     nproc          32768
* hard     nproc          32768
* soft     nofile         32768
* hard     nofile         32768
root soft     nproc          32768
root hard     nproc          32768
root soft     nofile         32768
root hard     nofile         32768
EOF

#-----------------------------------------------
# 8. Memory management (gentle cleanup)
#-----------------------------------------------
cat > /etc/cron.hourly/memory-management << 'EOF'
#!/bin/bash
USED=$(free | awk '/^Mem/ {print int($3/$2 * 100)}')
if [ "$USED" -gt 85 ]; then
    sync
    echo 1 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory
fi
EOF
chmod +x /etc/cron.hourly/memory-management

#-----------------------------------------------
# 9. Load and persist BBR
#-----------------------------------------------
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

#-----------------------------------------------
# 10. CPU Frequency Scaling (if available)
#-----------------------------------------------
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu" 2>/dev/null || true
    done
fi

echo -e "${GREEN}Optimization complete! System configured for 1GB RAM VPS.${NC}"
echo -e "${GREEN}Please reboot your system to apply all changes.${NC}"
