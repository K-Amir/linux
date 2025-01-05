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
# 3. Setup Swap (2GB)
#-----------------------------------------------
if [ ! -f /swapfile ]; then
    echo -e "${GREEN}Creating 2GB swap file...${NC}"
    dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # Optimize swap settings
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
# System limits - reduced for 1GB RAM
fs.file-max = 32768
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 32768

# TCP optimization - conservative values
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.optmem_max = 32768
net.ipv4.tcp_rmem = 4096 262144 4194304
net.ipv4.tcp_wmem = 4096 262144 4194304
net.ipv4.udp_rmem_min = 4096
net.ipv4.udp_wmem_min = 4096

# Enhanced TCP stability settings
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 5
net.ipv4.ip_local_port_range = 1024 65535

# Conservative TCP keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Reduced connection tracking
net.netfilter.nf_conntrack_max = 32768
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Memory optimization for 1GB RAM
vm.swappiness = 30
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 32768
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 300

# TCP memory limits - adjusted for 1GB RAM
net.ipv4.tcp_mem = 32768 65536 262144
net.ipv4.tcp_max_tw_buckets = 32768
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 4096

# IPv6 optimizations (conservative)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-xray-complete.conf

#-----------------------------------------------
# 6. Network interface optimization (conservative)
#-----------------------------------------------
# Enable basic network offloading
ethtool -K ${DEFAULT_NIC} tso on gso on gro on 2>/dev/null || true

# Set moderate ring buffer sizes
ethtool -G ${DEFAULT_NIC} rx 1024 tx 1024 2>/dev/null || true

# Moderate interrupt coalescence
ethtool -C ${DEFAULT_NIC} rx-usecs 50 tx-usecs 50 2>/dev/null || true

# Moderate queue length
ip link set dev ${DEFAULT_NIC} txqueuelen 5000 2>/dev/null || true

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
