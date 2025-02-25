#!/bin/bash
# Optimized Xray/V2Ray VLESS+Reality Configuration Script for 1GB RAM Ubuntu
# Supports Ubuntu 22.04–24.04
# Use with caution – tune settings to your workload/environment.
# Author: Your Name
# Date: 2025-02-01

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

echo -e "${GREEN}Starting optimized Xray/V2Ray configuration for 1GB RAM VPS...${NC}"

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
    curl wget unzip ethtool haveged irqbalance htop iftop

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
echo -e "${GREEN}Applying optimized sysctl settings...${NC}"
cat > /etc/sysctl.d/99-xray.conf << 'EOF'
# Optimized settings for VLESS+Reality under low-memory conditions

# Increase file descriptors and inotify limits
fs.file-max = 1048576
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288

# TCP and network performance optimizations
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 16384
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.optmem_max = 131072
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

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

# Aggressive TCP keepalive for responsiveness
net.ipv4.tcp_keepalive_time = 15
net.ipv4.tcp_keepalive_intvl = 3
net.ipv4.tcp_keepalive_probes = 3

# Connection tracking optimizations
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 180
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 10
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 1

# Virtual memory tuning
vm.swappiness = 5
vm.vfs_cache_pressure = 40
vm.min_free_kbytes = 65536
vm.dirty_ratio = 10
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 300
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory limits and timeouts
net.ipv4.tcp_mem = 262144 524288 1048576
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_max_orphans = 131072
net.ipv4.tcp_moderate_rcvbuf = 1

# High-speed and low-latency tweaks
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1

# IPv6 settings (enable if needed)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

# Apply the sysctl settings
sysctl --system

########################################
# 5.1 Ensure conntrack module is loaded
########################################
echo -e "${GREEN}Ensuring connection tracking module is loaded...${NC}"
modprobe nf_conntrack || true
# Add to modules-load to ensure it's loaded on boot
if ! grep -q "^nf_conntrack" /etc/modules-load.d/modules.conf 2>/dev/null; then
    echo "nf_conntrack" >> /etc/modules-load.d/modules.conf
fi

# Create directory if it doesn't exist
mkdir -p /etc/modules-load.d/

# Ensure conntrack hashsize is set appropriately for high connection loads
if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
    # Set hashsize to 1/4 of max for optimal performance
    CONNTRACK_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
    HASHSIZE=$((CONNTRACK_MAX / 4))
    
    # Create or update the conntrack configuration
    if [ -d /etc/modprobe.d ]; then
        echo "options nf_conntrack hashsize=$HASHSIZE" > /etc/modprobe.d/nf_conntrack.conf
    fi
fi

# Ensure the conntrack table doesn't get full under heavy load
if [ -f /proc/sys/net/netfilter/nf_conntrack_buckets ]; then
    echo -e "${GREEN}Current conntrack statistics:${NC}"
    echo "Current conntrack count: $(cat /proc/sys/net/netfilter/nf_conntrack_count)"
    echo "Maximum conntrack: $(cat /proc/sys/net/netfilter/nf_conntrack_max)"
    echo "Conntrack buckets: $(cat /proc/sys/net/netfilter/nf_conntrack_buckets)"
fi

########################################
# 6. Optimize Network Interface Settings
########################################
echo -e "${GREEN}Optimizing network interface settings on '$DEFAULT_NIC'...${NC}"

# Enable offloading features
ethtool -K "$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Set ring buffer sizes - check current values first
echo -e "${GREEN}Current ring buffer settings:${NC}"
ethtool -g "$DEFAULT_NIC" 2>/dev/null || true

# Set ring buffer sizes to maximum supported values
CURRENT_RX_MAX=$(ethtool -g "$DEFAULT_NIC" 2>/dev/null | grep -A 5 "Pre-set maximums" | grep "RX" | awk '{print $2}' || echo "4096")
CURRENT_TX_MAX=$(ethtool -g "$DEFAULT_NIC" 2>/dev/null | grep -A 5 "Pre-set maximums" | grep "TX" | awk '{print $2}' || echo "4096")

echo -e "${GREEN}Setting ring buffers to maximum supported values: RX=$CURRENT_RX_MAX, TX=$CURRENT_TX_MAX${NC}"
ethtool -G "$DEFAULT_NIC" rx "$CURRENT_RX_MAX" tx "$CURRENT_TX_MAX" 2>/dev/null || true

# Adjust interrupt coalescence for high-throughput, low-latency VPN traffic
echo -e "${GREEN}Optimizing interrupt coalescence for VPN workloads...${NC}"
ethtool -C "$DEFAULT_NIC" adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null || true

# Increase transmit queue length for many simultaneous connections
echo -e "${GREEN}Increasing transmit queue length...${NC}"
ip link set dev "$DEFAULT_NIC" txqueuelen 10000 2>/dev/null || true

# Optimize network interface for high connection count
echo -e "${GREEN}Applying advanced network optimizations for high connection count...${NC}"

# Install additional network tools if needed
DEBIAN_FRONTEND=noninteractive apt-get install -y ifupdown net-tools || true

# Disable TCP timestamps to reduce CPU overhead
ethtool -K "$DEFAULT_NIC" tx-tcp-segmentation on 2>/dev/null || true
ethtool -K "$DEFAULT_NIC" tx-tcp-ecn-segmentation on 2>/dev/null || true
ethtool -K "$DEFAULT_NIC" tx-checksum-ipv4 on 2>/dev/null || true
ethtool -K "$DEFAULT_NIC" tx-checksum-ipv6 on 2>/dev/null || true

# Optimize for many small packets (typical in VPN traffic)
ethtool -K "$DEFAULT_NIC" rx-checksum on 2>/dev/null || true
ethtool -K "$DEFAULT_NIC" tx-scatter-gather on 2>/dev/null || true
ethtool -K "$DEFAULT_NIC" scatter-gather on 2>/dev/null || true

# Increase the number of RPS (Receive Packet Steering) queues
# This distributes packet processing across CPU cores
NUM_CORES=$(nproc)
MAX_RPS_CPUS=$((2**NUM_CORES - 1))
RPS_CPUS_MASK=$(printf "%x" $MAX_RPS_CPUS)

for RPS_DIR in /sys/class/net/"$DEFAULT_NIC"/queues/rx-*; do
    echo "$RPS_CPUS_MASK" > "$RPS_DIR/rps_cpus" 2>/dev/null || true
done

# Set RFS (Receive Flow Steering) settings
echo 32768 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
for RFS_DIR in /sys/class/net/"$DEFAULT_NIC"/queues/rx-*; do
    echo 32768 > "$RFS_DIR/rps_flow_cnt" 2>/dev/null || true
done

# Set XPS (Transmit Packet Steering) settings
for XPS_DIR in /sys/class/net/"$DEFAULT_NIC"/queues/tx-*; do
    echo "$RPS_CPUS_MASK" > "$XPS_DIR/xps_cpus" 2>/dev/null || true
done

# Persist network optimizations across reboots
cat > /etc/network/if-up.d/network-tuning << EOF
#!/bin/bash
# Network interface tuning for VPN workloads

# Apply settings to $DEFAULT_NIC
if [ "\$IFACE" = "$DEFAULT_NIC" ] || [ "\$IFACE" = "all" ]; then
    # Set ring buffer sizes
    ethtool -G $DEFAULT_NIC rx $CURRENT_RX_MAX tx $CURRENT_TX_MAX 2>/dev/null || true
    
    # Set interrupt coalescence
    ethtool -C $DEFAULT_NIC adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null || true
    
    # Set queue length
    ip link set dev $DEFAULT_NIC txqueuelen 10000 2>/dev/null || true
    
    # Enable offloading features
    ethtool -K $DEFAULT_NIC tso on gso on gro on sg on tx on rx on 2>/dev/null || true
    
    # Set RPS/RFS/XPS
    echo $RPS_CPUS_MASK > /sys/class/net/$DEFAULT_NIC/queues/rx-0/rps_cpus 2>/dev/null || true
    echo 32768 > /sys/class/net/$DEFAULT_NIC/queues/rx-0/rps_flow_cnt 2>/dev/null || true
    echo $RPS_CPUS_MASK > /sys/class/net/$DEFAULT_NIC/queues/tx-0/xps_cpus 2>/dev/null || true
fi
EOF

chmod +x /etc/network/if-up.d/network-tuning

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
# 8. (Optional) Memory Management Cron Job
########################################
# Note: Modern kernels manage memory caches well. This cron job is optional and intended
# for systems under heavy memory pressure. Remove if not needed.
echo -e "${GREEN}Installing advanced memory management system...${NC}"

# Create a more sophisticated memory management script
cat > /usr/local/bin/memory-manager << 'EOF'
#!/bin/bash
# Advanced memory management for V2Ray/Xray VPN nodes
# This script monitors memory usage and takes appropriate actions
# to prevent OOM killer from terminating critical services
# Modified to avoid service restarts completely except when service is down

# Configuration
MEMORY_THRESHOLD=90       # Threshold to trigger initial actions
CRITICAL_THRESHOLD=97     # Threshold for more aggressive actions
SWAP_THRESHOLD=95         # Threshold for swap usage concern
LOG_FILE="/var/log/memory-manager.log"
V2RAY_SERVICE="x-ui"      # Using x-ui panel service instead of direct xray/v2ray
ALERT_FILE="/tmp/memory_alert"  # File to track alerts for external monitoring

# Ensure log file exists
touch "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# Get current memory usage percentage
get_memory_usage() {
    free | awk '/^Mem/ {printf "%.0f", $3/$2 * 100}'
}

# Get current swap usage percentage
get_swap_usage() {
    free | awk '/^Swap/ {if ($2 > 0) printf "%.0f", $3/$2 * 100; else print "0"}'
}

# Get top memory consumers
get_top_processes() {
    ps aux --sort=-%mem | head -n 6 | awk '{print $2, $4, $11}' | tail -n +2
}

# Check if x-ui service is running
is_v2ray_running() {
    systemctl is-active --quiet "$V2RAY_SERVICE" && return 0 || return 1
}

# Main logic
MEM_USAGE=$(get_memory_usage)
SWAP_USAGE=$(get_swap_usage)

if [ "$MEM_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
    log "High memory usage detected: ${MEM_USAGE}%"
    log "Current swap usage: ${SWAP_USAGE}%"
    
    # Log top memory consumers
    log "Top memory consumers:"
    TOP_PROCS=$(get_top_processes)
    log "$TOP_PROCS"
    
    # Check if x-ui service is running - only restart if it's not running at all
    # This is the ONLY case where we restart the service
    if ! is_v2ray_running; then
        log "WARNING: $V2RAY_SERVICE is not running! Attempting to restart..."
        x-ui restart
    fi
    
    # Take action based on severity - focus on clearing caches, never restart running services
    if [ "$MEM_USAGE" -gt "$CRITICAL_THRESHOLD" ]; then
        # Critical memory pressure - take aggressive action but NEVER restart running services
        log "CRITICAL: Memory usage above ${CRITICAL_THRESHOLD}%. Taking emergency actions."
        sync
        echo 3 > /proc/sys/vm/drop_caches
        echo 1 > /proc/sys/vm/compact_memory
        
        # Create alert file for external monitoring systems
        if [ "$SWAP_USAGE" -gt "$SWAP_THRESHOLD" ]; then
            log "SEVERE ALERT: Both memory (${MEM_USAGE}%) and swap (${SWAP_USAGE}%) at critical levels!"
            echo "CRITICAL_MEMORY_ALERT: $(date)" > "$ALERT_FILE"
            echo "Memory: ${MEM_USAGE}%" >> "$ALERT_FILE"
            echo "Swap: ${SWAP_USAGE}%" >> "$ALERT_FILE"
            echo "Top processes:" >> "$ALERT_FILE"
            echo "$TOP_PROCS" >> "$ALERT_FILE"
            
            # Try to identify and log large memory consumers for manual investigation
            log "Large memory consumers (processes using >100MB):"
            ps -eo pid,ppid,cmd,%mem,%cpu,rss --sort=-rss | awk '$7>102400' >> "$LOG_FILE"
            
            # Additional aggressive memory freeing actions
            # Attempt to reclaim slab objects
            log "Attempting to reclaim slab objects..."
            echo 2 > /proc/sys/vm/drop_caches
            
            # Attempt to compact memory more aggressively
            log "Attempting aggressive memory compaction..."
            for i in $(find /sys/devices/system/node/node*/compact -type f 2>/dev/null); do
                echo 1 > "$i" 2>/dev/null || true
            done
        fi
    elif [ "$MEM_USAGE" -gt 95 ]; then
        # High memory pressure - clear page cache and dentries
        log "HIGH: Memory usage above 95%. Clearing page cache and dentries."
        sync
        echo 2 > /proc/sys/vm/drop_caches
        echo 1 > /proc/sys/vm/compact_memory
        
        # Remove alert file if it exists but we're below critical threshold
        [ -f "$ALERT_FILE" ] && rm -f "$ALERT_FILE"
    else
        # Moderate memory pressure
        log "MODERATE: Memory usage above ${MEMORY_THRESHOLD}%. Clearing page cache."
        sync
        echo 1 > /proc/sys/vm/drop_caches
        
        # Remove alert file if it exists but we're below critical threshold
        [ -f "$ALERT_FILE" ] && rm -f "$ALERT_FILE"
    fi
    
    # Log memory usage after actions
    sleep 2
    NEW_MEM_USAGE=$(get_memory_usage)
    log "Memory usage after actions: ${NEW_MEM_USAGE}%"
else
    # Remove alert file if memory usage is normal
    [ -f "$ALERT_FILE" ] && rm -f "$ALERT_FILE"
    # Optional: Log normal operation (uncomment if you want regular logs)
    # log "Normal memory usage: ${MEM_USAGE}%"
    :
fi

# Rotate log file if it gets too large (>1MB)
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt 1048576 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
fi
EOF

chmod +x /usr/local/bin/memory-manager

# Create a cron job to run the memory manager every 10 minutes (was 5 minutes)
cat > /etc/cron.d/memory-manager << 'EOF'
# Run memory management script every 10 minutes
*/10 * * * * root /usr/local/bin/memory-manager >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/memory-manager

# Create a logrotate configuration for the memory manager log
cat > /etc/logrotate.d/memory-manager << 'EOF'
/var/log/memory-manager.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

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
# 10. Set CPU Frequency Scaling to "Performance"
########################################
echo -e "${GREEN}Setting CPU scaling governor to 'performance' (if supported)...${NC}"
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu_gov" 2>/dev/null || true
    done
fi

########################################
# 11. Optimize I/O Scheduling and Process Priority
########################################
echo -e "${GREEN}Optimizing I/O scheduling and process priorities...${NC}"

# Install necessary tools if not already installed
DEBIAN_FRONTEND=noninteractive apt-get install -y util-linux

# Set I/O scheduler to deadline for better performance under load
for disk in $(lsblk -d -o NAME | grep -v NAME); do
    if [ -f "/sys/block/$disk/queue/scheduler" ]; then
        echo "Setting I/O scheduler for $disk to deadline"
        echo "deadline" > "/sys/block/$disk/queue/scheduler" 2>/dev/null || true
        
        # Optimize I/O settings for VPN workloads
        echo 4096 > "/sys/block/$disk/queue/read_ahead_kb" 2>/dev/null || true
        echo 0 > "/sys/block/$disk/queue/add_random" 2>/dev/null || true
        echo 256 > "/sys/block/$disk/queue/nr_requests" 2>/dev/null || true
    fi
done

# Create a systemd service to set Xray/V2Ray process priority
cat > /etc/systemd/system/v2ray-priority.service << 'EOF'
[Unit]
Description=Set V2Ray/Xray Process Priority (x-ui)
After=x-ui.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for pid in $(pgrep -f "xray|v2ray|x-ui"); do renice -n -10 $pid; ionice -c 1 -n 0 -p $pid; done'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the priority service
systemctl daemon-reload
systemctl enable v2ray-priority.service
systemctl start v2ray-priority.service || true

# Create a script to periodically check and adjust V2Ray/Xray priority
cat > /usr/local/bin/adjust-v2ray-priority << 'EOF'
#!/bin/bash
# This script ensures V2Ray/Xray processes always have high priority
# Updated for x-ui panel

# Find V2Ray/Xray and x-ui processes
V2RAY_PIDS=$(pgrep -f "xray|v2ray|x-ui")

if [ -n "$V2RAY_PIDS" ]; then
    for pid in $V2RAY_PIDS; do
        # Set CPU priority (nice level)
        current_nice=$(ps -o ni -p $pid | tail -n1 | tr -d ' ')
        if [ "$current_nice" -gt -10 ]; then
            renice -n -10 $pid >/dev/null 2>&1
        fi
        
        # Set I/O priority to real-time class
        ionice -c 1 -n 0 -p $pid >/dev/null 2>&1
    done
fi
EOF

chmod +x /usr/local/bin/adjust-v2ray-priority

# Add to cron to run every 15 minutes
cat > /etc/cron.d/v2ray-priority << 'EOF'
# Adjust V2Ray/Xray process priority every 15 minutes
*/15 * * * * root /usr/local/bin/adjust-v2ray-priority >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/v2ray-priority

########################################
# 12. Install Performance Monitoring Tools
########################################
echo -e "${GREEN}Installing performance monitoring tools...${NC}"

# Install essential monitoring tools
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    sysstat \
    nload \
    iotop \
    dstat \
    vnstat \
    nethogs \
    lsof \
    tcpdump \
    mtr-tiny

# Configure sysstat to collect data every 5 minutes
if [ -f /etc/default/sysstat ]; then
    sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
    sed -i 's|^5-55\/10|\*/5|' /etc/cron.d/sysstat
    systemctl enable sysstat
    systemctl restart sysstat
fi

# Set up vnstat for network traffic monitoring
if command -v vnstat >/dev/null; then
    vnstat -u -i "$DEFAULT_NIC"
    systemctl enable vnstat
    systemctl restart vnstat
fi

# Create a simple performance snapshot script
cat > /usr/local/bin/vpn-performance << 'EOF'
#!/bin/bash
# VPN Performance Snapshot Tool
# Captures key performance metrics for V2Ray/Xray VPN nodes

OUTPUT_DIR="/var/log/vpn-performance"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
SNAPSHOT_FILE="$OUTPUT_DIR/snapshot-$TIMESTAMP.log"
V2RAY_SERVICE="x-ui"  # Using x-ui panel instead of direct xray/v2ray

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Start the snapshot
echo "=== VPN Performance Snapshot ($TIMESTAMP) ===" > "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# System uptime and load
echo "=== System Uptime and Load ===" >> "$SNAPSHOT_FILE"
uptime >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# Memory usage
echo "=== Memory Usage ===" >> "$SNAPSHOT_FILE"
free -h >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# Disk usage
echo "=== Disk Usage ===" >> "$SNAPSHOT_FILE"
df -h >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# CPU info and usage
echo "=== CPU Information ===" >> "$SNAPSHOT_FILE"
lscpu | grep -E 'Model name|^CPU\(s\)|MHz|Thread|Core' >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"
echo "=== CPU Usage (top 10 processes) ===" >> "$SNAPSHOT_FILE"
ps aux --sort=-%cpu | head -11 >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# Network connections
echo "=== Network Connections Summary ===" >> "$SNAPSHOT_FILE"
echo "Total connections: $(netstat -an | wc -l)" >> "$SNAPSHOT_FILE"
echo "TCP connections: $(netstat -ant | wc -l)" >> "$SNAPSHOT_FILE"
echo "UDP connections: $(netstat -anu | wc -l)" >> "$SNAPSHOT_FILE"
echo "ESTABLISHED connections: $(netstat -ant | grep ESTABLISHED | wc -l)" >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# V2Ray/Xray status via x-ui
echo "=== V2Ray/Xray Status (x-ui) ===" >> "$SNAPSHOT_FILE"
systemctl status "$V2RAY_SERVICE" >> "$SNAPSHOT_FILE" 2>&1
echo "" >> "$SNAPSHOT_FILE"

# V2Ray/Xray process info
echo "=== V2Ray/Xray Process Information ===" >> "$SNAPSHOT_FILE"
V2RAY_PID=$(pgrep -f "xray|v2ray")
if [ -n "$V2RAY_PID" ]; then
    echo "Process ID: $V2RAY_PID" >> "$SNAPSHOT_FILE"
    echo "CPU usage: $(ps -p "$V2RAY_PID" -o %cpu | tail -1)%" >> "$SNAPSHOT_FILE"
    echo "Memory usage: $(ps -p "$V2RAY_PID" -o %mem | tail -1)%" >> "$SNAPSHOT_FILE"
    echo "Running since: $(ps -p "$V2RAY_PID" -o lstart | tail -1)" >> "$SNAPSHOT_FILE"
    echo "Open files: $(lsof -p "$V2RAY_PID" | wc -l)" >> "$SNAPSHOT_FILE"
    echo "TCP connections: $(lsof -p "$V2RAY_PID" -a -i tcp | wc -l)" >> "$SNAPSHOT_FILE"
    echo "UDP connections: $(lsof -p "$V2RAY_PID" -a -i udp | wc -l)" >> "$SNAPSHOT_FILE"
else
    echo "V2Ray/Xray process not found!" >> "$SNAPSHOT_FILE"
fi

# Also check x-ui process
echo "" >> "$SNAPSHOT_FILE"
echo "=== x-ui Panel Process Information ===" >> "$SNAPSHOT_FILE"
XUI_PID=$(pgrep -f "x-ui")
if [ -n "$XUI_PID" ]; then
    echo "Process ID: $XUI_PID" >> "$SNAPSHOT_FILE"
    echo "CPU usage: $(ps -p "$XUI_PID" -o %cpu | tail -1)%" >> "$SNAPSHOT_FILE"
    echo "Memory usage: $(ps -p "$XUI_PID" -o %mem | tail -1)%" >> "$SNAPSHOT_FILE"
    echo "Running since: $(ps -p "$XUI_PID" -o lstart | tail -1)" >> "$SNAPSHOT_FILE"
    echo "Open files: $(lsof -p "$XUI_PID" | wc -l)" >> "$SNAPSHOT_FILE"
else
    echo "x-ui panel process not found!" >> "$SNAPSHOT_FILE"
fi
echo "" >> "$SNAPSHOT_FILE"

# Network interface statistics
echo "=== Network Interface Statistics ($DEFAULT_NIC) ===" >> "$SNAPSHOT_FILE"
ifconfig "$DEFAULT_NIC" >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"
if command -v vnstat >/dev/null; then
    echo "=== VnStat Traffic Statistics ===" >> "$SNAPSHOT_FILE"
    vnstat -i "$DEFAULT_NIC" >> "$SNAPSHOT_FILE"
    echo "" >> "$SNAPSHOT_FILE"
fi

# Connection tracking information
echo "=== Connection Tracking Information ===" >> "$SNAPSHOT_FILE"
echo "Current connections: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "N/A")" >> "$SNAPSHOT_FILE"
echo "Maximum connections: $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "N/A")" >> "$SNAPSHOT_FILE"
echo "Connection usage: $(awk "BEGIN {printf \"%.2f%%\", $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0) * 100 / $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 1)}")" >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

# Kernel parameters
echo "=== Key Kernel Parameters ===" >> "$SNAPSHOT_FILE"
echo "TCP congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)" >> "$SNAPSHOT_FILE"
echo "Default qdisc: $(sysctl -n net.core.default_qdisc)" >> "$SNAPSHOT_FILE"
echo "File max: $(sysctl -n fs.file-max)" >> "$SNAPSHOT_FILE"
echo "Open files: $(lsof | wc -l)" >> "$SNAPSHOT_FILE"
echo "" >> "$SNAPSHOT_FILE"

echo "Performance snapshot saved to: $SNAPSHOT_FILE"
echo "Run 'cat $SNAPSHOT_FILE' to view the results"
EOF

chmod +x /usr/local/bin/vpn-performance

# Create a daily cron job to capture performance data
cat > /etc/cron.d/vpn-performance << 'EOF'
# Capture VPN performance data 4 times a day
0 */6 * * * root /usr/local/bin/vpn-performance >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/vpn-performance

# Create a logrotate configuration for performance snapshots
cat > /etc/logrotate.d/vpn-performance << 'EOF'
/var/log/vpn-performance/snapshot-*.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

echo -e "${GREEN}Performance monitoring tools installed. Run 'vpn-performance' to generate a snapshot.${NC}"

########################################
# Final Message
########################################
echo -e "${GREEN}Optimization complete!${NC}"
echo -e "${GREEN}Most settings have been applied immediately, though a reboot is recommended for full effect.${NC}"

# Print a summary of the optimizations
echo -e "\n${GREEN}=== Optimization Summary ===${NC}"
echo -e "✓ System limits increased for high connection counts"
echo -e "✓ Network buffers and TCP parameters optimized for VPN workloads"
echo -e "✓ Memory management improved with intelligent monitoring"
echo -e "✓ Connection tracking optimized for thousands of simultaneous connections"
echo -e "✓ I/O scheduling tuned for VPN traffic patterns"
echo -e "✓ Process priority management for V2Ray/Xray"
echo -e "✓ Network interface optimized for maximum throughput"
echo -e "✓ Performance monitoring tools installed"
echo -e "✓ BBR congestion control enabled"
echo -e "✓ CPU set to performance mode"

# Print available tools and commands
echo -e "\n${GREEN}=== Available Tools ===${NC}"
echo -e "• Run '${GREEN}vpn-performance${NC}' to generate a performance snapshot"
echo -e "• View logs at '${GREEN}/var/log/memory-manager.log${NC}' for memory management actions"
echo -e "• Performance snapshots stored in '${GREEN}/var/log/vpn-performance/${NC}'"
echo -e "• Use '${GREEN}htop${NC}' for real-time system monitoring"
echo -e "• Use '${GREEN}nload${NC}' to monitor network bandwidth usage"
echo -e "• Use '${GREEN}vnstat -l -i $DEFAULT_NIC${NC}' for live network traffic statistics"
echo -e "• Use '${GREEN}nethogs $DEFAULT_NIC${NC}' to see which processes are using bandwidth"

# Print next steps
echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo -e "1. ${GREEN}Reboot your system${NC} to ensure all optimizations take effect"
echo -e "2. Monitor your system performance with the installed tools"
echo -e "3. Check V2Ray/Xray logs if you encounter any issues"
echo -e "4. Adjust the memory threshold in /usr/local/bin/memory-manager if needed"

echo -e "\n${GREEN}Your VPS is now optimized for handling hundreds to thousands of V2Ray/Xray VLESS+REALITY connections!${NC}"
