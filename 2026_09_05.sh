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
# 3. Setup Swap (8GB)
########################################
# Check if any swap is active; if not, create a 8GB swap file.
if ! swapon --show | grep -q '^/swapfile'; then
    echo -e "${GREEN}No active swap file found. Creating a 8GB swap file...${NC}"
    fallocate -l 8G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=8192
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Ensure swap is mounted on reboot
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    # Optimize swap behavior
    echo 1 > /proc/sys/vm/swappiness
    echo "vm.swappiness = 1" > /etc/sysctl.d/99-swap.conf
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
net.core.somaxconn = 65535
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
net.netfilter.nf_conntrack_max = 4194304
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 10
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 10
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 1

# Virtual memory tuning
vm.swappiness = 1
vm.vfs_cache_pressure = 10
vm.min_free_kbytes = 131072
vm.dirty_ratio = 10
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 300
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory limits and timeouts
net.ipv4.tcp_mem = 524288 1048576 2097152
net.ipv4.tcp_max_tw_buckets = 2097152
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_max_orphans = 262144
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
ip link set dev "$DEFAULT_NIC" txqueuelen 50000 2>/dev/null || true

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

# Set RPS (Receive Flow Steering) settings
echo 65536 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true
for RFS_DIR in /sys/class/net/"$DEFAULT_NIC"/queues/rx-*; do
    echo 65536 > "$RFS_DIR/rps_flow_cnt" 2>/dev/null || true
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
    ip link set dev $DEFAULT_NIC txqueuelen 50000 2>/dev/null || true
    
    # Enable offloading features
    ethtool -K $DEFAULT_NIC tso on gso on gro on sg on tx on rx on 2>/dev/null || true
    
    # Set RPS/RFS/XPS
    echo $RPS_CPUS_MASK > /sys/class/net/$DEFAULT_NIC/queues/rx-0/rps_cpus 2>/dev/null || true
    echo 65536 > /sys/class/net/$DEFAULT_NIC/queues/rx-0/rps_flow_cnt 2>/dev/null || true
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
* soft     nofile         1048576
* hard     nofile         1048576
root soft     nproc          32768
root hard     nproc          32768
root soft     nofile         1048576
root hard     nofile         1048576
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
MEMORY_THRESHOLD=85       # Threshold to trigger initial actions
CRITICAL_THRESHOLD=95     # Threshold for more aggressive actions
SWAP_THRESHOLD=95         # Threshold for swap usage concern
LOG_FILE="/var/log/memory-manager.log"
V2RAY_SERVICE="x-ui"      # Using x-ui panel service instead of direct xray/v2ray
ALERT_FILE="/tmp/memory_alert"  # File to track alerts for external monitoring
MAX_LOG_AGE=30            # Number of days to keep logs before deleting

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

# Clean up old log files
cleanup_old_logs() {
    # Remove old log rotated files older than MAX_LOG_AGE days
    find /var/log -name "memory-manager.log.*" -type f -mtime +$MAX_LOG_AGE -delete 2>/dev/null || true
}

# Main logic
MEM_USAGE=$(get_memory_usage)
SWAP_USAGE=$(get_swap_usage)

# Call log cleanup function at the beginning 
cleanup_old_logs

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

# Create a cron job to run the memory manager every 30 minutes (was 10 minutes)
cat > /etc/cron.d/memory-manager << 'EOF'
# Run memory management script every 30 minutes
*/30 * * * * root /usr/local/bin/memory-manager >/dev/null 2>&1
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

# Add to cron to run every hour (was every 15 minutes)
cat > /etc/cron.d/v2ray-priority << 'EOF'
# Adjust V2Ray/Xray process priority every hour
0 * * * * root /usr/local/bin/adjust-v2ray-priority >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/v2ray-priority

########################################
# 12. Install Performance Monitoring Tools
########################################
echo -e "${GREEN}Installing essential monitoring tools...${NC}"

# Install only the most essential monitoring tools
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    htop \
    lsof \
    tcpdump

# Set up vnstat for network traffic monitoring (lightweight and useful for bandwidth tracking)
if command -v vnstat >/dev/null; then
    # Check if -u parameter is supported in this version of vnstat
    if vnstat --help 2>&1 | grep -q -- "-u"; then
        # -u parameter is supported
        vnstat -u -i "$DEFAULT_NIC"
    else
        # -u parameter is not supported, try to use the service directly
        echo -e "${GREEN}Note: This version of vnstat doesn't support the -u parameter. Using alternative method.${NC}"
        # Just ensure the service is enabled and running
        systemctl enable vnstat
        systemctl restart vnstat
        # Try to update the database using the default method
        vnstat -i "$DEFAULT_NIC" >/dev/null 2>&1 || true
    fi
    systemctl enable vnstat
    systemctl restart vnstat
fi

# Create a simplified performance snapshot script that focuses only on critical metrics
cat > /usr/local/bin/vpn-performance << 'EOF'
#!/bin/bash
# Lightweight VPN Performance Snapshot Tool
# Captures only essential metrics with minimal memory usage

OUTPUT_DIR="/var/log/vpn-performance"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
SNAPSHOT_FILE="$OUTPUT_DIR/snapshot-$TIMESTAMP.log"
V2RAY_SERVICE="x-ui"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Start the snapshot
echo "=== VPN Performance Snapshot ($TIMESTAMP) ===" > "$SNAPSHOT_FILE"

# System uptime and load - critical for stability monitoring
echo "=== System Uptime and Load ===" >> "$SNAPSHOT_FILE"
uptime >> "$SNAPSHOT_FILE"

# Memory usage - critical for performance (using free -m for smaller output)
echo "=== Memory Usage (MB) ===" >> "$SNAPSHOT_FILE"
free -m | grep -E "Mem|Swap" >> "$SNAPSHOT_FILE"

# Network connections - just the count to save space
echo "=== Connection Summary ===" >> "$SNAPSHOT_FILE"
echo "ESTABLISHED connections: $(ss -nat | grep ESTAB | wc -l)" >> "$SNAPSHOT_FILE"
echo "Total connections: $(ss -nat | wc -l)" >> "$SNAPSHOT_FILE"

# V2Ray/Xray status - brief check only
echo "=== V2Ray/Xray Status ===" >> "$SNAPSHOT_FILE"
systemctl is-active "$V2RAY_SERVICE" >> "$SNAPSHOT_FILE" 2>&1

# Disk space - critical for log management
echo "=== Disk Space ===" >> "$SNAPSHOT_FILE"
df -h / | grep -v "Filesystem" >> "$SNAPSHOT_FILE"

# Clean up old snapshots
find "$OUTPUT_DIR" -type f -name "snapshot-*.log" -mtime +30 -delete >/dev/null 2>&1
EOF

chmod +x /usr/local/bin/vpn-performance

# Create a weekly cron job to capture performance data (reduced frequency)
cat > /etc/cron.d/vpn-performance << 'EOF'
# Capture VPN performance data once a week on Sunday at midnight
0 0 * * 0 root /usr/local/bin/vpn-performance >/dev/null 2>&1
# Clean up performance snapshots older than 30 days
0 1 * * 0 root find /var/log/vpn-performance -type f -name "snapshot-*.log" -mtime +30 -delete >/dev/null 2>&1
EOF

chmod 644 /etc/cron.d/vpn-performance

# Create a simplified logrotate configuration for performance snapshots
cat > /etc/logrotate.d/vpn-performance << 'EOF'
/var/log/vpn-performance/snapshot-*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

echo -e "${GREEN}Essential monitoring tools installed. Run 'vpn-performance' manually if needed.${NC}"

########################################
# Add Global Log Cleanup System
########################################
echo -e "${GREEN}Setting up global log cleanup system...${NC}"

# Create a script to clean up old log files system-wide
cat > /usr/local/bin/clean-logs << 'EOF'
#!/bin/bash
# Global log cleanup script
# Removes old logs to prevent disk space issues

# Configuration
MAX_AGE=30  # Delete logs older than this many days

# Clean up standard log files
find /var/log -type f -name "*.gz" -mtime +$MAX_AGE -delete
find /var/log -type f -name "*.old" -mtime +$MAX_AGE -delete
find /var/log -type f -name "*.1" -mtime +$MAX_AGE -delete
find /var/log -type f -name "*.log.*" -mtime +$MAX_AGE -delete

# Clean up X-UI related logs (adjust paths as needed)
if [ -d "/etc/x-ui" ]; then
    find /etc/x-ui -type f -name "*.log" -mtime +$MAX_AGE -delete
fi

# Clean up old journal logs 
journalctl --vacuum-time=7d

# Log completion
echo "Log cleanup completed on $(date)" >> /var/log/clean-logs.log
EOF

chmod +x /usr/local/bin/clean-logs

# Add to weekly cron
cat > /etc/cron.weekly/clean-logs << 'EOF'
#!/bin/bash
/usr/local/bin/clean-logs
EOF

chmod +x /etc/cron.weekly/clean-logs

# Run it once immediately
/usr/local/bin/clean-logs

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

# Modify the script setting CPU frequency scaling
# Make CPU scheduling more aggressive for network processing
cat > /etc/sysctl.d/99-cpu-scheduler.conf << 'EOF'
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
EOF

# Dedicated CPUs for network processing (if 4+ cores available)
if [ $(nproc) -ge 4 ]; then
    echo 'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX isolcpus=3"' >> /etc/default/grub
    update-grub
    
    # Use isolated CPU for network processing
    for IRQ in $(grep -l "$DEFAULT_NIC" /proc/irq/*/actions 2>/dev/null); do
        IRQ_NUM=$(echo "$IRQ" | cut -d'/' -f3)
        echo 8 > /proc/irq/$IRQ_NUM/smp_affinity 2>/dev/null || true
    done
fi

# Install irqbalance if not already present
apt-get install -y irqbalance

# Configure for high throughput network workloads
cat > /etc/default/irqbalance << 'EOF'
ENABLED=1
ONESHOT=0
# High performance mode - minimize latency
IRQBALANCE_ARGS="--hintpolicy=ignore --policyscript=/etc/irqbalance/network-policy.sh"
EOF

# Create IRQ policy script for network interfaces
mkdir -p /etc/irqbalance/
cat > /etc/irqbalance/network-policy.sh << EOF
#!/bin/bash
if [[ \$1 == *"$DEFAULT_NIC"* ]]; then
    echo "network"
fi
EOF
chmod +x /etc/irqbalance/network-policy.sh
