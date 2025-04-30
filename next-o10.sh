#!/bin/bash
# Ultimate Xray/V2Ray Optimization Script (Revised)
# Optimized for Hiddify clients on Windows using system proxy in censored networks
# Supports Ubuntu 22.04-24.04
# With TCP-BRUTAL option for extreme performance
# Incorporates fixes based on review (rng-tools, DNS, memory, conntrack, etc.)

# Exit on error, undefined variable, or failure in a pipeline.
set -euo pipefail

# Color definitions for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Ensure the script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

echo -e "${GREEN}Starting ultimate Xray/V2Ray configuration for 1GB RAM VPS with Windows/Wi-Fi fixes...${NC}"

########################################
# 1. Detect the Default Network Interface
########################################
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${YELLOW}Could not detect default interface using 'ip route'. Trying 'ip link'...${NC}"
    # Fallback: get the first non-loopback, non-docker interface
    DEFAULT_NIC=$(ip -o link show | awk -F': ' '$2 != "lo" && $2 !~ /docker|veth|br-/ {print $2; exit}')
    if [[ -z "$DEFAULT_NIC" ]]; then
        echo -e "${RED}Error: Could not automatically detect a suitable network interface.${NC}"
        # Attempt a common default as a last resort
        DEFAULT_NIC="eth0"
        echo -e "${YELLOW}Falling back to assuming interface is '$DEFAULT_NIC'. Please verify!${NC}"
    fi
fi
echo -e "${GREEN}Detected network interface: $DEFAULT_NIC${NC}"

# Verify the interface exists
if ! ip link show "$DEFAULT_NIC" >/dev/null 2>&1; then
    echo -e "${RED}Error: Network interface '$DEFAULT_NIC' not found or invalid.${NC}"
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
    iproute2 vnstat nethogs rng-tools mtr traceroute build-essential dkms \
    linux-headers-$(uname -r) git cpufrequtils logrotate

########################################
# 3. Setup Swap (4GB)
########################################
# Check if any swap is active; if not, create a 4GB swap file.
if ! swapon --show | grep -q '^/swapfile'; then
    echo -e "${GREEN}No active swap file found. Creating a 4GB swap file...${NC}"
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Ensure swap is mounted on reboot
    if ! grep -q '/swapfile *none *swap *sw *0 *0' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo -e "${GREEN}4GB Swap file created and activated.${NC}"
    # Swappiness will be set via sysctl later
else
    echo -e "${GREEN}Swap is already active. Skipping swap file creation.${NC}"
fi

########################################
# 4. Backup Existing sysctl Configuration
########################################
if [[ -f /etc/sysctl.conf ]]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d-%H%M%S)
    echo -e "${GREEN}Backed up /etc/sysctl.conf${NC}"
fi
# Also backup any existing custom sysctl files
mkdir -p /etc/sysctl.d.backup.$(date +%Y%m%d-%H%M%S)
cp /etc/sysctl.d/*.conf /etc/sysctl.d.backup.$(date +%Y%m%d-%H%M%S)/ 2>/dev/null || true
echo -e "${GREEN}Backed up existing files in /etc/sysctl.d/${NC}"

########################################
# 5. Apply Memory-Optimized sysctl Settings
########################################
# This file is overwritten each time the script is run.
echo -e "${GREEN}Applying optimized sysctl settings (tuned for 1GB RAM) with Wi-Fi/Windows fixes...${NC}"
cat > /etc/sysctl.d/99-xray-optimizations.conf << 'EOF'
# Optimized settings for VLESS+Reality under low-memory conditions (1GB RAM target)

# --- Basic Networking ---
# Enable IP forwarding (critical for tunneling/VPN)
net.ipv4.ip_forward = 1

# --- System Limits ---
# Increase file descriptors and inotify limits
fs.file-max = 65535
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 32768

# --- TCP/UDP Buffer Tuning (Reduced for 1GB RAM) ---
net.core.somaxconn = 16384 # Increased backlog for listening sockets
net.core.netdev_max_backlog = 8192 # Increased packet queue size per NIC
# Reduced buffer sizes to conserve kernel memory on low-RAM systems
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 4194304 # Reduced from 8M
net.core.wmem_max = 4194304 # Reduced from 8M
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 262144 4194304 # Reduced max
net.ipv4.tcp_wmem = 4096 262144 4194304 # Reduced max
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
# Total TCP memory limits (pages) - Reduced significantly
# Format: min, pressure, max (pages; 1 page = 4096 bytes)
# Example: 786432 pages = 3GB; Reduce max to ~512MB (131072 pages)
net.ipv4.tcp_mem = 98304 131072 196608 # Reduced max/pressure

# --- TCP Behavior Tuning ---
# Real-time application optimizations
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_thin_dupack = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0

# XTLS Vision Flow / General Compatibility
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
# TCP Fast Open DISABLED - causes issues with some routers/networks
net.ipv4.tcp_fastopen = 0
# ECN DISABLED - causes issues with some routers/networks
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_timestamps = 1 # Needed for tcp_tw_reuse
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
# Modified for more forgiving behavior on unstable networks
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 10 # Default is 15, slightly less aggressive
net.ipv4.ip_local_port_range = 1024 65535

# AGGRESSIVE TCP keepalive for NAT traversal (check if needed)
net.ipv4.tcp_keepalive_time = 60 # Default 7200s
net.ipv4.tcp_keepalive_intvl = 15 # Default 75s
net.ipv4.tcp_keepalive_probes = 5 # Default 9

# Connection tracking optimizations
net.netfilter.nf_conntrack_max = 131072 # Max entries (adjust based on expected connections)
# Reduced established timeout to 1 hour (from 2 hours in original script, default is ~5 days)
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_be_liberal = 1 # More lenient tracking

# --- Congestion Control (Set later based on choice) ---
# Default qdisc set to fq (Fair Queue) - works well with BBR/CAKE
net.core.default_qdisc = fq
# Congestion control will be set to 'bbr' or 'brutal' later

# --- Virtual Memory Tuning (Balanced for 1GB RAM Server) ---
vm.swappiness = 10 # Use swap moderately when needed (Consistent value)
vm.vfs_cache_pressure = 75 # Slightly less aggressive cache retention than 50
vm.min_free_kbytes = 16384 # Minimum free memory kernel tries to maintain
vm.dirty_ratio = 20 # Max % memory for dirty pages
vm.dirty_background_ratio = 5 # Lower % memory to start background writeback
vm.dirty_expire_centisecs = 1500 # Flush dirty data after 15s
vm.dirty_writeback_centisecs = 500 # Wake flusher every 5s
vm.page-cluster = 0 # Disable readahead (saves RAM, may impact sequential read)

# --- TCP Time-Wait / Orphan / Backlog ---
net.ipv4.tcp_max_tw_buckets = 65536 # Reduced from 131k
net.ipv4.tcp_fin_timeout = 30 # Default 60, faster cleanup
net.ipv4.tcp_max_syn_backlog = 8192 # Reduced from 32k
net.ipv4.tcp_max_orphans = 32768 # Reduced from 65k
net.ipv4.tcp_moderate_rcvbuf = 1 # Enable buffer auto-tuning

# --- High-speed / Low-latency / Reliability ---
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_workaround_signed_windows = 1
net.ipv4.tcp_limit_output_bytes = 262144
net.ipv4.tcp_tw_reuse = 1 # Reuse TIME_WAIT sockets (requires timestamps)
net.ipv4.tcp_frto = 1 # Enable Forward RTO-Recovery

# --- Security / DoS Mitigation ---
net.ipv4.tcp_syncookies = 1 # Mitigate SYN floods

# --- Path MTU Discovery ---
net.ipv4.ip_no_pmtu_disc = 0 # Enable PMTU discovery
# net.ipv4.ip_forward_use_pmtu = 1 # Use discovered PMTU for forwarded packets (can be problematic)

# --- Fragmentation ---
# net.ipv4.ipfrag_high_thresh = 4194304 # Max memory for IP fragments (default often okay)
# net.ipv4.ipfrag_time = 30 # Time to keep fragments (default 60)

# --- IPv6 Settings (Optional - uncomment to disable if not needed) ---
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
# Uncomment below lines to disable IPv6 completely if unused
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1
# net.ipv6.conf.lo.disable_ipv6 = 1

EOF

# Apply the sysctl settings
sysctl --system

########################################
# 6. Optimize Network Interface Settings
########################################
echo -e "${GREEN}Optimizing network interface settings on '$DEFAULT_NIC'...${NC}"

# Enable common offloading features (ignore errors if not supported)
ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Set ring buffer sizes (use more memory for potentially better burst handling)
# Monitor memory if issues arise
ethtool -G "$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null || true

# Adjust interrupt coalescence - Adaptive is often best unless tuning specifically
# ethtool -C "$DEFAULT_NIC" adaptive-rx on adaptive-tx on 2>/dev/null || true
# Example fixed values (use with caution):
# ethtool -C "$DEFAULT_NIC" rx-usecs 125 tx-usecs 125 2>/dev/null || true

# Set transmit queue length - REDUCED TO PREVENT BUFFERBLOAT
# Made persistent via systemd service later
ip link set dev "$DEFAULT_NIC" txqueuelen 500 2>/dev/null || true

########################################
# 7. Set System Limits for Xray/V2Ray
########################################
echo -e "${GREEN}Applying system limits for Xray/V2Ray...${NC}"
cat > /etc/security/limits.d/99-xray-limits.conf << 'EOF'
# Increased limits for high-connection services like Xray/V2Ray
* soft     nproc          65535
* hard     nproc          65535
* soft     nofile         65535
* hard     nofile         65535
root soft     nproc          65535
root hard     nproc          65535
root soft     nofile         65535
root hard     nofile         65535
EOF

########################################
# 8. Apply TCP MSS Clamping (Critical for Windows clients / some networks)
########################################
echo -e "${GREEN}Applying TCP MSS clamping (1360 bytes) for compatibility...${NC}"
# Check if rule exists before adding to prevent duplicates
# IPv4
if ! iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null; then
    iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
    echo -e "${GREEN}IPv4 MSS clamp rule added.${NC}"
else
    echo -e "${YELLOW}IPv4 MSS clamp rule already exists.${NC}"
fi

# IPv6 (only if IPv6 is not disabled in sysctl)
if [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -eq 0 ]]; then
    if ! ip6tables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360 2>/dev/null; then
        ip6tables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
        echo -e "${GREEN}IPv6 MSS clamp rule added.${NC}"
    else
        echo -e "${YELLOW}IPv6 MSS clamp rule already exists.${NC}"
    fi
else
    echo -e "${YELLOW}IPv6 is disabled, skipping IPv6 MSS clamping.${NC}"
fi

# Persist the rules
netfilter-persistent save

########################################
# 9. Choose and Load Congestion Control Algorithm
########################################
echo -e "${GREEN}Setting up TCP congestion control...${NC}"

# Function to install TCP-BRUTAL kernel module
install_tcp_brutal() {
    echo -e "${YELLOW}Attempting to install TCP-BRUTAL for extreme performance...${NC}"
    
    # Ensure required packages are installed (already done in step 2)
    
    # Clone TCP-BRUTAL if not already present
    if [ ! -d "/tmp/TCP-BRUTAL" ]; then
        cd /tmp
        git clone https://github.com/Locke-Shi/TCP-BRUTAL
    fi
    
    cd /tmp/TCP-BRUTAL
    
    # Clean previous build attempts
    make clean || true
    
    # Build and install the module using DKMS if possible
    if command -v dkms &> /dev/null; then
        # Check if already added to DKMS
        if ! dkms status | grep -q 'tcp_brutal'; then
            cp -r . /usr/src/tcp_brutal-1.0 # Version number can be arbitrary
            # Create DKMS config
            cat > /usr/src/tcp_brutal-1.0/dkms.conf <<EOF
PACKAGE_NAME="tcp_brutal"
PACKAGE_VERSION="1.0"
BUILT_MODULE_NAME[0]="tcp_brutal"
DEST_MODULE_LOCATION[0]="/kernel/net/ipv4"
AUTOINSTALL="yes"
MAKE[0]="'make' KERNELDIR=/lib/modules/\${kernelver}/build"
CLEAN="'make' clean"
EOF
            dkms add -m tcp_brutal -v 1.0
        fi
        # Build and install for current kernel
        dkms build -m tcp_brutal -v 1.0 || { echo -e "${RED}DKMS build failed!${NC}"; return 1; }
        dkms install -m tcp_brutal -v 1.0 || { echo -e "${RED}DKMS install failed!${NC}"; return 1; }
    else
        # Fallback to manual build and install (less robust across kernel updates)
        make || { echo -e "${RED}Make failed!${NC}"; return 1; }
        insmod tcp_brutal.ko || { echo -e "${RED}insmod failed!${NC}"; return 1; }
        # Make the module load at boot (manual method)
        cp tcp_brutal.ko /lib/modules/$(uname -r)/kernel/net/ipv4/
        if ! grep -q "^tcp_brutal" /etc/modules-load.d/tcp_brutal.conf 2>/dev/null; then
             echo "tcp_brutal" > /etc/modules-load.d/tcp_brutal.conf
        fi
        depmod -a
    fi
    
    # Activate TCP-BRUTAL via sysctl
    echo "net.ipv4.tcp_congestion_control = brutal" > /etc/sysctl.d/98-tcp-congestion.conf
    sysctl -w net.ipv4.tcp_congestion_control=brutal
    
    cd /
    echo -e "${GREEN}TCP-BRUTAL installed and activated successfully!${NC}"
    return 0
}

# Ask about TCP-BRUTAL
echo -e "${YELLOW}Available TCP Congestion Control Algorithms:${NC}"
sysctl net.ipv4.tcp_available_congestion_control
echo ""
echo -e "${YELLOW}BBR is the recommended safe choice for most environments.${NC}"
echo -e "${YELLOW}TCP-BRUTAL is experimental, potentially much faster, but may cause instability or ISP issues.${NC}"
read -p "Would you like to try installing TCP-BRUTAL? (y/N): " -r tcp_brutal_choice

if [[ "$tcp_brutal_choice" =~ ^[Yy]$ ]]; then
    if install_tcp_brutal; then
        echo -e "${GREEN}TCP-BRUTAL setup complete.${NC}"
    else
        echo -e "${RED}TCP-BRUTAL installation failed. Falling back to BBR.${NC}"
        # Ensure BBR is loaded and set
        modprobe tcp_bbr || true
        if ! grep -q "^tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
            echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        fi
        echo "net.ipv4.tcp_congestion_control = bbr" > /etc/sysctl.d/98-tcp-congestion.conf
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        echo -e "${GREEN}Using standard BBR congestion control.${NC}"
    fi
else
    echo -e "${GREEN}Setting up standard BBR congestion control...${NC}"
    # Check if BBR is available and set it
    if sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr; then
        modprobe tcp_bbr || true # Load module if needed
        if ! grep -q "^tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
             echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        fi
        echo "net.ipv4.tcp_congestion_control = bbr" > /etc/sysctl.d/98-tcp-congestion.conf
        sysctl -w net.ipv4.tcp_congestion_control=bbr
        echo -e "${GREEN}BBR congestion control activated.${NC}"
    else
        echo -e "${YELLOW}BBR does not seem to be available in your kernel. Using default (likely cubic).${NC}"
        # Remove any specific congestion control setting file
        rm -f /etc/sysctl.d/98-tcp-congestion.conf
        # Rely on kernel default
        sysctl -w net.ipv4.tcp_congestion_control=$(sysctl -n net.ipv4.tcp_congestion_control | awk '{print $1}') # Re-apply default
    fi
fi

########################################
# 10. Configure DNS Resolvers via systemd-resolved
########################################
echo -e "${GREEN}Setting up DNS resolvers via systemd-resolved for reliability...${NC}"
# Use resolvectl to set DNS servers for the default interface
# Using Cloudflare, Google, Quad9
resolvectl dns "$DEFAULT_NIC" 1.1.1.1 8.8.8.8 9.9.9.9
# Set domains to '~.' to indicate these servers handle all domains
resolvectl domain "$DEFAULT_NIC" '~.'

# Verify the changes
echo -e "${GREEN}Current DNS settings for $DEFAULT_NIC:${NC}"
resolvectl status "$DEFAULT_NIC" | grep 'DNS Servers' -A 2

# Ensure systemd-resolved is enabled and running
systemctl enable systemd-resolved.service
systemctl start systemd-resolved.service

########################################
# 11. Network Queue Optimization (CAKE / FQ_CODEL)
########################################
echo -e "${GREEN}Setting up network queue management (CAKE preferred)...${NC}"

# Script to apply QoS settings
cat > /usr/local/bin/apply-qos.sh << EOF
#!/bin/bash
set -euo pipefail

IFACE="\$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print \$5; exit}')"
if [[ -z "\$IFACE" ]]; then
    IFACE="\$(ip -o link show | awk -F': ' '\$2 != "lo" && \$2 !~ /docker|veth|br-/ {print \$2; exit}')"
    if [[ -z "\$IFACE" ]]; then
        echo "Error: Could not detect network interface for QoS." >&2
        exit 1
    fi
fi

# --- IMPORTANT: Set your actual bandwidth here! ---
# Examples: 100mbit, 500mbit, 1gbit
# Setting this correctly is crucial for CAKE/FQ_CODEL effectiveness.
BANDWIDTH="1gbit" # MODIFY THIS VALUE

# Clear existing root qdisc
tc qdisc del dev \$IFACE root 2>/dev/null || true
echo "Applying QoS settings to \$IFACE with bandwidth \$BANDWIDTH..."

# Check if CAKE module is available
if modprobe sch_cake 2>/dev/null || lsmod | grep -q sch_cake; then
    echo "CAKE module found. Applying CAKE qdisc..."
    # Apply CAKE with sensible defaults for VPN traffic
    # nat: Helps with NAT traversal performance
    # dual-srchost/dual-dsthost: Better fairness for multiple internal/external IPs
    # wash: Clean DSCP markings if they cause issues
    # ack-filter: Aggressive ACK filtering for asymmetric links (use with caution)
    tc qdisc add dev \$IFACE root cake bandwidth \$BANDWIDTH nat dual-srchost besteffort # Consider adding 'ack-filter' if needed
    echo "CAKE qdisc applied."
else
    echo "CAKE module not found. Falling back to FQ_CODEL..."
    # Apply FQ_CODEL directly as the root qdisc (simpler than HTB + FQ_CODEL)
    # FQ_CODEL provides fair queuing and AQM without complex configuration.
    tc qdisc add dev \$IFACE root fq_codel
    echo "FQ_CODEL qdisc applied."
    # Note: FQ_CODEL doesn't require explicit bandwidth setting like CAKE/HTB,
    # but works best when underlying driver/sysctl settings (like txqueuelen) are reasonable.
fi

# Optional: Show applied qdisc
tc qdisc show dev \$IFACE
EOF

chmod +x /usr/local/bin/apply-qos.sh

# Systemd service to apply QoS at boot
cat > /etc/systemd/system/apply-qos.service << 'EOF'
[Unit]
Description=Apply Network QoS Settings (CAKE/FQ_CODEL)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-qos.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the QoS service
systemctl daemon-reload
systemctl enable apply-qos.service
# Try starting it now, might fail if network isn't fully up yet, but will run on reboot
systemctl restart apply-qos.service || echo -e "${YELLOW}QoS service failed to start immediately, should apply on reboot.${NC}"

########################################
# 12. Make txqueuelen Setting Persistent
########################################
echo -e "${GREEN}Making txqueuelen=500 setting persistent...${NC}"
cat > /etc/systemd/system/set-txqueuelen.service << EOF
[Unit]
Description=Set txqueuelen=500 on default network interface
After=network.target

[Service]
Type=oneshot
# Use bash -c to handle the subshell correctly for finding the interface
ExecStart=/bin/bash -c 'IFACE=\$(ip route get 1.1.1.1 2>/dev/null | awk "/dev/ {print \\\$5; exit}"); if [[ -z "\$IFACE" ]]; then IFACE=\$(ip -o link show | awk -F": " "\\\$2 != \\"lo\\" && \\\$2 !~ /docker|veth|br-/ {print \\\$2; exit}"); fi; if [[ -n "\$IFACE" ]]; then ip link set dev "\$IFACE" txqueuelen 500; else echo "Could not find interface for txqueuelen" >&2; exit 1; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable set-txqueuelen.service
systemctl restart set-txqueuelen.service || echo -e "${YELLOW}txqueuelen service failed to start immediately, should apply on reboot.${NC}"

########################################
# 13. Network Performance Monitoring Service
########################################
echo -e "${GREEN}Setting up network performance monitoring service...${NC}"
# Monitoring script
cat > /usr/local/bin/network-monitor.sh << 'EOF'
#!/bin/bash
LOGFILE="/var/log/network-performance.log"
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}' || ip -o link show | awk -F': ' '$2 != "lo" && $2 !~ /docker|veth|br-/ {print $2; exit}')

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOGFILE")"

check_performance() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "===== $TIMESTAMP =====" >> "$LOGFILE"

    # Check latency and packet loss to common destinations
    for host in 1.1.1.1 8.8.8.8 9.9.9.9; do
        echo "--- MTR to $host ---" >> "$LOGFILE"
        mtr -n -c 1 -r $host >> "$LOGFILE" 2>&1 || echo "mtr to $host failed" >> "$LOGFILE"
        echo "--- Ping to $host ---" >> "$LOGFILE"
        ping -c 5 -W 2 $host >> "$LOGFILE" 2>&1 || echo "Ping to $host failed" >> "$LOGFILE"
        echo "" >> "$LOGFILE"
    done

    # Log connection counts by state
    echo "--- TCP Connection States ---" >> "$LOGFILE"
    if command -v ss &>/dev/null; then
        ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -nr >> "$LOGFILE"
    else
        netstat -tan | awk 'NR>2 {print $6}' | sort | uniq -c | sort -nr >> "$LOGFILE"
    fi

    # Log conntrack count
    if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then
        echo "--- Conntrack Count ---" >> "$LOGFILE"
        cat /proc/sys/net/netfilter/nf_conntrack_count >> "$LOGFILE"
    fi

    # Log bandwidth usage (if vnstat is available and interface detected)
    if command -v vnstat &>/dev/null && [ -n "$IFACE" ]; then
        echo "--- Bandwidth Usage ($IFACE) ---" >> "$LOGFILE"
        vnstat -i "$IFACE" -h 1 | tail -n 5 >> "$LOGFILE"
    fi

    echo "" >> "$LOGFILE" # Empty line for readability
}

# Run performance check every 15 minutes (900 seconds)
while true; do
    check_performance
    sleep 900
done
EOF

chmod +x /usr/local/bin/network-monitor.sh

# Systemd service for the monitor
cat > /etc/systemd/system/network-monitor.service << 'EOF'
[Unit]
Description=Network Performance Monitor
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/network-monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Log rotation configuration for the monitor log
cat > /etc/logrotate.d/network-monitor << 'EOF'
/var/log/network-performance.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF

echo -e "${GREEN}Log rotation configured for /var/log/network-performance.log${NC}"

# Enable and start the monitor service
systemctl daemon-reload
systemctl enable network-monitor.service
systemctl start network-monitor.service

########################################
# 14. Enable Hardware Entropy Gathering (rng-tools)
########################################
echo -e "${GREEN}Enabling hardware entropy gathering service (rng-tools)...${NC}"
# Ensure rng-tools package is installed (done in step 2)
# The service name is typically rng-tools.service or rngd.service
# Check for common service names
SERVICE_NAME="rng-tools.service"
if ! systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    if systemctl list-unit-files | grep -q "rngd.service"; then
        SERVICE_NAME="rngd.service"
    else
        echo -e "${YELLOW}Could not find standard rng-tools service (rng-tools.service or rngd.service). Skipping.${NC}"
        SERVICE_NAME="" # Clear service name if not found
    fi
fi

if [ -n "$SERVICE_NAME" ]; then
    echo -e "${GREEN}Found entropy service: $SERVICE_NAME. Enabling and starting...${NC}"
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
else
    echo -e "${YELLOW}Skipping rng-tools service management.${NC}"
fi

# Enable haveged as a fallback/supplement if installed
if command -v haveged &> /dev/null; then
    echo -e "${GREEN}Enabling and starting haveged service...${NC}"
    systemctl enable haveged.service
    systemctl start haveged.service
fi

########################################
# 15. Set CPU Frequency Scaling to "Performance"
########################################
echo -e "${GREEN}Setting CPU scaling governor to 'performance' (if supported)...${NC}"
if command -v cpufreq-set &> /dev/null; then
    # Set governor for all cores
    for cpu_num in $(seq 0 $(($(nproc --all) - 1))); do
        cpufreq-set -c "$cpu_num" -g performance 2>/dev/null || true
    done
    echo -e "${GREEN}CPU governor set to performance.${NC}"
    # Make CPU governor setting persistent via cpufrequtils default config
    if [ -f /etc/default/cpufrequtils ]; then
        # Check if GOVERNOR is already set, if not, add it
        if ! grep -q '^GOVERNOR=' /etc/default/cpufrequtils; then
            echo 'GOVERNOR="performance"' >> /etc/default/cpufrequtils
        else
            # If set, modify it
            sed -i 's/^GOVERNOR=.*/GOVERNOR="performance"/' /etc/default/cpufrequtils
        fi
        echo -e "${GREEN}Made CPU governor setting persistent.${NC}"
    else
         echo -e "${YELLOW}Cannot find /etc/default/cpufrequtils to make governor persistent.${NC}"
    fi
    # Ensure the service is enabled (it might be disabled by default on some systems)
    systemctl enable cpufrequtils || true
    systemctl restart cpufrequtils || true

else
    echo -e "${YELLOW}cpufrequtils not found or CPU scaling not supported. Skipping governor setting.${NC}"
fi

########################################
# 16. Daily System Maintenance Cron Job
########################################
echo -e "${GREEN}Setting up daily system maintenance tasks (safe version)...${NC}"
cat > /etc/cron.daily/system-maintenance << 'EOF'
#!/bin/bash
# Daily maintenance tasks

echo "Running daily maintenance on $(date)"

# Clean up apt cache
echo "Cleaning apt cache..."
apt-get clean

# Remove unused packages (use with caution if unsure)
# echo "Removing unused packages..."
# apt-get autoremove -y

# Update package lists
echo "Updating package lists..."
apt-get update

# Consider adding log cleanup using logrotate configurations instead of manual find/delete

echo "Daily maintenance finished."

# NOTE: The dangerous 'conntrack -F' command has been REMOVED.
# Do NOT add 'conntrack -F' here as it disconnects all active sessions.
EOF

chmod +x /etc/cron.daily/system-maintenance

########################################
# Final Configuration Summary
########################################
echo -e "${GREEN}Optimization complete! Key changes applied:${NC}"
echo "1. Optimized sysctl settings for 1GB RAM (reduced buffers)."
echo "2. Consistent vm.swappiness=10."
echo "3. TCP MSS Clamping to 1360 bytes (persistent)."
echo "4. Disabled TCP Fast Open and ECN for compatibility."
echo "5. Aggressive TCP keepalives for NAT traversal."
echo "6. Reduced TCP established connection timeout (nf_conntrack) to 1 hour."
echo "7. Corrected DNS configuration using systemd-resolved."
echo "8. Configured QoS (CAKE preferred, fallback FQ_CODEL) - ${YELLOW}Remember to set BANDWIDTH in /usr/local/bin/apply-qos.sh!${NC}"
echo "9. Persistent txqueuelen=500."
echo "10. Network monitoring service with log rotation (/var/log/network-performance.log)."
echo "11. Corrected rng-tools/haveged service handling."
echo "12. Set CPU governor to 'performance' (persistent)."
echo "13. Safe daily cron job (removed conntrack flush)."

# Show chosen congestion control
CONGESTION_CONTROL=$(sysctl -n net.ipv4.tcp_congestion_control)
echo "14. TCP Congestion Control set to: ${GREEN}$CONGESTION_CONTROL${NC}"

# Show IP Tables rules
echo "15. IP TABLES MSS CLAMPING RULES (FORWARD chain):"
iptables -t mangle -L FORWARD -v -n | grep TCPMSS || echo " (No IPv4 rule found)"
if [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -eq 0 ]]; then
    echo "16. IP6 TABLES MSS CLAMPING RULES (FORWARD chain):"
    ip6tables -t mangle -L FORWARD -v -n | grep TCPMSS || echo " (No IPv6 rule found)"
fi

echo ""
echo -e "${YELLOW}Most settings have been applied. A reboot is recommended to ensure all changes take effect properly (especially kernel modules and limits).${NC}"
echo -e "${YELLOW}Network performance logs: /var/log/network-performance.log${NC}"
echo -e "${YELLOW}QoS Script (edit bandwidth): /usr/local/bin/apply-qos.sh${NC}"

# Ask if user wants to reboot now
read -p "Would you like to reboot now? (y/N): " -r reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
else
    echo "Reboot skipped. Please reboot manually when convenient."
fi

exit 0
