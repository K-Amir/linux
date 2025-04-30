#!/bin/bash
# Ultimate Xray/V2Ray Optimization Script
# Optimized for Hiddify clients on Windows using system proxy in censored networks
# Supports Ubuntu 22.04-24.04
# With TCP-BRUTAL option for extreme performance

# Exit on error, undefined variable, or failure in a pipeline.
set -euo pipefail

# Color definitions for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m' 
RED='\033[0;31m'
NC='\033[0m'

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

echo -e "${GREEN}Starting ultimate Xray/V2Ray configuration for 1GB RAM VPS with Windows/Wi-Fi fixes...${NC}"

########################################
# 1. Detect the Default Network Interface
########################################
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${YELLOW}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

# Verify the interface exists
if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo -e "${RED}Error: Network interface '$DEFAULT_NIC' not found${NC}"
    exit 1
fi

########################################
# 2. Install Essential Packages
########################################
# This script is targeted for Ubuntu/Debian
echo -e "${GREEN}Updating package repositories and installing essential packages...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance htop iftop iptables-persistent \
    tc vnstat nethogs rng-tools5 mtr traceroute

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
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d)
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
net.ipv4.tcp_mtu_probing = 1
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

# Socket buffer auto-tuning enhancements
net.ipv4.tcp_workaround_signed_windows = 1
net.ipv4.tcp_limit_output_bytes = 262144

# Additional reliability
net.ipv4.tcp_tw_reuse = 1 # Added for potentially faster socket reuse
net.ipv4.tcp_frto = 1 # Added for better loss recovery

# TCP SYN Cookie protection (DoS mitigation)
net.ipv4.tcp_syncookies = 1

# Smart Path MTU Discovery settings
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.ip_forward_use_pmtu = 1

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
# 9. Choose and Load Congestion Control Algorithm
########################################
echo -e "${GREEN}Setting up TCP congestion control...${NC}"

# Function to install TCP-BRUTAL kernel module
install_tcp_brutal() {
    echo -e "${YELLOW}Installing TCP-BRUTAL for extreme performance...${NC}"
    
    # Install dependencies
    apt-get install -y git build-essential dkms linux-headers-$(uname -r)
    
    # Clone and compile TCP-BRUTAL
    cd /tmp
    git clone https://github.com/Locke-Shi/TCP-BRUTAL
    cd TCP-BRUTAL
    
    # Build and install the module
    make
    insmod tcp_brutal.ko
    
    # Make the module load at boot
    cp tcp_brutal.ko /lib/modules/$(uname -r)/kernel/net/ipv4/
    echo "tcp_brutal" >> /etc/modules-load.d/modules.conf
    depmod -a
    
    # Activate TCP-BRUTAL
    echo "net.ipv4.tcp_congestion_control = brutal" > /etc/sysctl.d/99-tcp-congestion.conf
    sysctl -w net.ipv4.tcp_congestion_control=brutal
    
    cd /
    echo -e "${GREEN}TCP-BRUTAL installed successfully!${NC}"
}

# Ask about TCP-BRUTAL
echo -e "${YELLOW}Would you like to install TCP-BRUTAL for extreme throughput? (y/n)${NC}"
echo -e "${YELLOW}Note: TCP-BRUTAL is experimental and may not be stable in all environments.${NC}"
echo -e "${YELLOW}BBR is the recommended safe choice for most environments.${NC}"
read -r tcp_brutal_choice

if [[ "$tcp_brutal_choice" =~ ^[Yy]$ ]]; then
    install_tcp_brutal
else
    echo -e "${GREEN}Using standard BBR congestion control...${NC}"
    # Check if BBR is active; note: if built into the kernel, modprobe may not be needed.
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        modprobe tcp_bbr || true
        # Persist the module on boot
        if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
            echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        fi
    fi
    # Set BBR as the congestion control algorithm
    echo "net.ipv4.tcp_congestion_control = bbr" > /etc/sysctl.d/99-tcp-congestion.conf
    sysctl -w net.ipv4.tcp_congestion_control=bbr
fi

########################################
# 10. Multiple DNS Resolvers for Redundancy
########################################
echo -e "${GREEN}Setting up multiple DNS resolvers for reliability...${NC}"
cat > /etc/resolv.conf << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
options rotate timeout:2 attempts:3
EOF

# Make resolv.conf immutable to prevent overwriting
# leave systemd-resolved in control; add extra upstreams
resolvectl dns "$DEFAULT_NIC" 1.1.1.1 9.9.9.9 8.8.8.8
resolvectl domain "$DEFAULT_NIC" '~.'

########################################
# 11. Network Queue Optimization
########################################
echo -e "${GREEN}Setting up advanced network queue management...${NC}"
cat > /usr/local/bin/network-queue.sh << 'EOF'
#!/bin/bash
IFACE=$(ip route get 1.1.1.1 | awk '/dev/ {print $5; exit}')

# Clear existing qdiscs
tc qdisc del dev $IFACE root 2>/dev/null || true

# If CAKE is available, use it (better than FQ + HTB)
if [ -d "/sys/module/sch_cake" ] || modprobe sch_cake 2>/dev/null; then
    tc qdisc add dev $IFACE root cake bandwidth 1Gbit rtt 50ms flows nat dual-srchost nonat nowash no-ack-filter split-gso
else
    # Fall back to HTB + FQ_CODEL
    tc qdisc add dev $IFACE root handle 1: htb default 30
    
    # Create main rate limit class (adjust for your bandwidth)
    tc class add dev $IFACE parent 1: classid 1:1 htb rate 1000mbit ceil 1000mbit
    
    # Create priority classes
    tc class add dev $IFACE parent 1:1 classid 1:10 htb rate 500mbit ceil 1000mbit prio 1
    tc class add dev $IFACE parent 1:1 classid 1:20 htb rate 300mbit ceil 800mbit prio 2
    tc class add dev $IFACE parent 1:1 classid 1:30 htb rate 200mbit ceil 500mbit prio 3
    
    # Add FQ_CODEL to spread traffic within each class
    tc qdisc add dev $IFACE parent 1:10 handle 10: fq_codel flows 1024 target 5ms interval 100ms
    tc qdisc add dev $IFACE parent 1:20 handle 20: fq_codel flows 1024 target 5ms interval 100ms
    tc qdisc add dev $IFACE parent 1:30 handle 30: fq_codel flows 1024 target 5ms interval 100ms
    
    # Filter traffic - VPN gets highest priority
    tc filter add dev $IFACE parent 1: protocol ip prio 1 u32 match ip dport 443 0xffff flowid 1:10
    tc filter add dev $IFACE parent 1: protocol ip prio 1 u32 match ip sport 443 0xffff flowid 1:10
    
    # Other interactive traffic gets medium priority
    tc filter add dev $IFACE parent 1: protocol ip prio 2 u32 match ip dport 80 0xffff flowid 1:20
    tc filter add dev $IFACE parent 1: protocol ip prio 2 u32 match ip sport 80 0xffff flowid 1:20
fi
EOF

chmod +x /usr/local/bin/network-queue.sh

# Add as a service to run at boot
cat > /etc/systemd/system/network-queue.service << 'EOF'
[Unit]
Description=Advanced Network Queue Management
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/network-queue.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable network-queue.service
systemctl start network-queue.service

########################################
# 12. Make txqueuelen Setting Persistent
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
# 13. Network Performance Monitoring
########################################
echo -e "${GREEN}Setting up network performance monitoring...${NC}"
cat > /usr/local/bin/network-monitor.sh << 'EOF'
#!/bin/bash
# Monitor network performance and log anomalies
LOGFILE="/var/log/network-performance.log"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOGFILE")"

check_performance() {
    # Log timestamp
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOGFILE"
    
    # Check latency to common destinations
    for host in 1.1.1.1 8.8.8.8; do
        ping -c 3 -W 2 $host 2>/dev/null | grep "time=" | awk '{print "Ping to '$host':", $7}' >> "$LOGFILE" || echo "Cannot reach $host" >> "$LOGFILE"
    done
    
    # Log connection counts by state
    echo "TCP Connection States:" >> "$LOGFILE"
    ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -nr >> "$LOGFILE"
    
    # Log bandwidth usage (if vnstat is available)
    if command -v vnstat &>/dev/null; then
        echo "Bandwidth Usage (last hour):" >> "$LOGFILE"
        vnstat -h 1 | tail -n 5 >> "$LOGFILE"
    fi
    
    echo "" >> "$LOGFILE" # Empty line for readability
}

# Run performance check every 15 minutes
while true; do
    check_performance
    sleep 900
done
EOF

chmod +x /usr/local/bin/network-monitor.sh

# Set up as a service
cat > /etc/systemd/system/network-monitor.service << 'EOF'
[Unit]
Description=Network Performance Monitor
After=network.target

[Service]
ExecStart=/usr/local/bin/network-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable network-monitor.service
systemctl start network-monitor.service

########################################
# 14. Enhanced TLS/SSL Performance
########################################
echo -e "${GREEN}Optimizing TLS/SSL performance...${NC}"

# Enable hardware entropy gathering for better TLS performance
systemctl enable rng-tools
systemctl start rng-tools

########################################
# 15. Set CPU Frequency Scaling to "Performance"
########################################
echo -e "${GREEN}Setting CPU scaling governor to 'performance' (if supported)...${NC}"
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu_gov" 2>/dev/null || true
    done
    
    # Make CPU governor setting persistent
    apt-get install -y cpufrequtils
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
fi

########################################
# 16. Daily System Maintenance (Optional)
########################################
echo -e "${GREEN}Setting up daily system maintenance tasks...${NC}"
cat > /etc/cron.daily/system-maintenance << 'EOF'
#!/bin/bash

# Clean up disk space
apt-get clean
apt-get autoremove -y

# Clear old logs
find /var/log -type f -name "*.log.*" -mtime +7 -delete
find /var/log -type f -name "*.gz" -mtime +7 -delete

# Update netfilter connection tracking table
conntrack -F

# Check for system updates (but don't install automatically)
apt-get update
EOF

chmod +x /etc/cron.daily/system-maintenance

########################################
# Final Configuration Summary
########################################
echo -e "${GREEN}Optimization complete with enhanced performance and Wi-Fi/Windows compatibility fixes!${NC}"
echo -e "${GREEN}Key optimizations implemented:${NC}"
echo "1. TCP MSS Clamping to 1360 bytes (fixes Windows MTU issues)"
echo "2. Disabled TCP Fast Open and ECN (problematic on ~5% of routers)"
echo "3. Aggressive TCP keepalives (60s instead of 300s for better NAT traversal)"
echo "4. Advanced network queue management (reduces bufferbloat, prioritizes VPN traffic)"
echo "5. Multiple DNS resolvers for reliability"
if [[ "$tcp_brutal_choice" =~ ^[Yy]$ ]]; then
    echo "6. TCP-BRUTAL congestion control (extreme performance mode)"
else
    echo "6. BBR congestion control (reliable performance mode)"
fi
echo "7. Performance monitoring and automated maintenance"

# Show IP Tables rules
echo "8. IP TABLES MSS CLAMPING:"
iptables -t mangle -L FORWARD -v -n | grep TCPMSS
echo "9. IP6 TABLES MSS CLAMPING:"
ip6tables -t mangle -L FORWARD -v -n | grep TCPMSS

echo -e "${YELLOW}Most settings have been applied immediately, though a reboot is recommended for full effect.${NC}"
echo -e "${YELLOW}Network performance logs will be available at: /var/log/network-performance.log${NC}"

# Ask if user wants to reboot now
echo -e "${GREEN}Would you like to reboot now to apply all changes? (y/n)${NC}"
read -r reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    echo "Reboot skipped. Please reboot manually when convenient."
fi
