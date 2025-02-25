#!/bin/bash
# Optimized Xray/V2Ray VLESS+Reality Configuration Script for 1GB RAM Ubuntu
# Supports Ubuntu 22.04–24.04
# Use with caution – tune settings to your workload/environment.
# Author: Your Name
# Date: 2025-02-25
# Version: 1.2.0

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
if ! apt-get update -y; then
    echo "Warning: Failed to update package repositories. Continuing anyway..."
fi

# Check if packages are already installed to avoid unnecessary reinstalls
PACKAGES="curl wget unzip ethtool haveged irqbalance htop iftop bc"
PACKAGES_TO_INSTALL=""
for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
    fi
done

# Only run apt-get install if there are packages to install
if [ ! -z "$PACKAGES_TO_INSTALL" ]; then
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES_TO_INSTALL; then
        echo "Warning: Failed to install some packages. This might affect script functionality."
        echo "Attempting to install packages individually..."
        
        # Try to install packages one by one
        for pkg in $PACKAGES_TO_INSTALL; do
            DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg || echo "Failed to install $pkg"
        done
    fi
fi

# Clean up package cache to free space
apt-get clean
apt-get autoremove -y

# Install earlyoom to prevent system hangs during extreme memory pressure
if ! dpkg -l | grep -q "^ii  earlyoom "; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y earlyoom || echo "Failed to install earlyoom"
    systemctl enable earlyoom 2>/dev/null || true
    systemctl start earlyoom 2>/dev/null || true
    # Configure earlyoom to be more aggressive but not overly so
    if [ -f /etc/default/earlyoom ]; then
        sed -i 's/^EARLYOOM_ARGS.*/EARLYOOM_ARGS="-r 60 -m 7 -M 12"/' /etc/default/earlyoom
        systemctl restart earlyoom 2>/dev/null || true
    fi
fi

########################################
# 3. Setup Swap (2GB instead of 4GB)
########################################
# Check if any swap is active; if not, create a 2GB swap file.
if ! swapon --show | grep -q '^/swapfile'; then
    echo -e "${GREEN}No active swap file found. Creating a 2GB swap file...${NC}"
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    # Ensure swap is mounted on reboot
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    # Set optimized swappiness for better performance
    echo 10 > /proc/sys/vm/swappiness
    cat > /etc/sysctl.d/99-swap.conf << EOF
# Optimized swap settings
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
else
    echo -e "${GREEN}Swap is already active. Applying optimized swappiness...${NC}"
    echo 10 > /proc/sys/vm/swappiness
    cat > /etc/sysctl.d/99-swap.conf << EOF
# Optimized swap settings
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
fi

# Add zswap for better swap performance if kernel supports it
if [ -d "/sys/module/zswap" ]; then
    echo -e "${GREEN}Enabling zswap for better swap performance...${NC}"
    echo "zswap.enabled=1" >> /etc/default/grub
    echo "zswap.compressor=lz4" >> /etc/default/grub
    echo "zswap.max_pool_percent=20" >> /etc/default/grub
    update-grub 2>/dev/null || echo "Warning: Failed to update grub, zswap settings may not persist after reboot"
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

# Balanced TCP keepalive (changed from 15,3,3 to 60,10,3)
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 3

# Connection tracking optimizations for thousands of users
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_buckets = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 300
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15
net.netfilter.nf_conntrack_tcp_be_liberal = 1

# BBR congestion control optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_ecn = 1

# Virtual memory tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 32768
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100
vm.page-cluster = 0

# TCP memory limits and timeouts for many concurrent connections
net.ipv4.tcp_mem = 131072 262144 524288
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_tw_reuse = 1

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

# Add security hardening
echo -e "${GREEN}Adding security hardening measures...${NC}"
cat > /etc/sysctl.d/99-security.conf << EOF
# Security hardening and DNS optimizations for censorship resistance
kernel.unprivileged_bpf_disabled = 1
kernel.kptr_restrict = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# DNS resolver settings for censorship resistance
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_syn_backlog = 30000
EOF
sysctl -p /etc/sysctl.d/99-security.conf

########################################
# 6. Optimize Network Interface Settings
########################################
echo -e "${GREEN}Optimizing network interface settings on '$DEFAULT_NIC'...${NC}"

# Function to safely run ethtool commands with better error reporting
run_ethtool() {
    local cmd=$1
    local feature=$2
    local state=$3
    if ! ethtool "$cmd" "$DEFAULT_NIC" "$feature" "$state" 2>/dev/null; then
        echo "Note: ethtool $cmd $feature command not supported on this interface or driver"
    fi
}

# Enable offloading features (fixed syntax)
run_ethtool -K tso on
run_ethtool -K gso on
run_ethtool -K gro on
run_ethtool -K sg on
run_ethtool -K tx on
run_ethtool -K rx on

# Set ring buffer sizes
if ! ethtool -G "$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null; then
    echo "Note: Setting ring buffer sizes not supported on this interface"
fi

# Adjust interrupt coalescence
if ! ethtool -C "$DEFAULT_NIC" adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null; then
    echo "Note: Setting interrupt coalescence not supported on this interface"
fi

# Increase transmit queue length
ip link set dev "$DEFAULT_NIC" txqueuelen 10000 2>/dev/null || true

########################################
# 7. Set System Limits for Xray/V2Ray
########################################
echo -e "${GREEN}Applying system limits for Xray/V2Ray...${NC}"
cat > /etc/security/limits.d/99-xray.conf << 'EOF'
* soft     nproc          131072
* hard     nproc          131072
* soft     nofile         1048576
* hard     nofile         1048576
root soft     nproc          131072
root hard     nproc          131072
root soft     nofile         1048576
root hard     nofile         1048576
EOF

########################################
# 8. Smarter Memory Management (replacing hourly cron job)
########################################
echo -e "${GREEN}Installing smarter memory management service...${NC}"
cat > /etc/systemd/system/memory-management.service << 'EOF'
[Unit]
Description=Smart Memory Management Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/memory-management.sh
Restart=always
RestartSec=300

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/memory-management.sh << 'EOF'
#!/bin/bash
# Smart memory management script
# This script runs as a service and only drops caches when necessary

# Function to log with timestamp
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Create memory usage log file
MEMORY_LOG="/var/log/v2ray-memory-usage.log"
touch $MEMORY_LOG
chmod 644 $MEMORY_LOG

# Function to check and optimize memory
check_memory() {
  # Get current timestamp
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Log memory stats hourly
  if [ $(date +%M) -eq "00" ]; then
    echo "$TIMESTAMP - Memory Total: ${MEM_TOTAL}KB, Free: ${MEM_FREE}KB, Available: ${MEM_AVAILABLE}KB (${MEM_AVAIL_PCT}%)" >> $MEMORY_LOG
    # Keep log file size reasonable
    tail -n 1000 $MEMORY_LOG > $MEMORY_LOG.tmp && mv $MEMORY_LOG.tmp $MEMORY_LOG
  fi
}

# Monitor every 3 minutes (more frequent checks for limited resources)
while true; do
  # Get memory stats
  MEM_TOTAL=$(free | grep Mem | awk '{print $2}')
  MEM_FREE=$(free | grep Mem | awk '{print $4}')
  MEM_BUFFERS=$(free | grep Mem | awk '{print $6}')
  MEM_CACHED=$(free | grep Mem | awk '{print $7}')
  
  # Calculate available memory percentage
  MEM_AVAILABLE=$((MEM_FREE + MEM_BUFFERS + MEM_CACHED))
  MEM_AVAIL_PCT=$((MEM_AVAILABLE * 100 / MEM_TOTAL))
  
  if [ $MEM_AVAIL_PCT -lt 10 ]; then
    log "Available memory critically low (${MEM_AVAIL_PCT}%). Freeing caches..."
    sync
    echo 1 > /proc/sys/vm/drop_caches
  elif [ $MEM_AVAIL_PCT -lt 15 ]; then
    # Check if Xray/V2Ray is using excessive memory
    V2RAY_MEM=$(ps aux | grep -E '(xray|v2ray)' | grep -v grep | awk '{print $4}' | sort -nr | head -1)
    if [[ -n "$V2RAY_MEM" ]] && (( $(echo "$V2RAY_MEM" | cut -d. -f1) > 40 )); then
      log "Xray/V2Ray using ${V2RAY_MEM}% memory with low available memory (${MEM_AVAIL_PCT}%). Restarting service..."
      if systemctl is-active --quiet xray; then
        systemctl restart xray
      elif systemctl is-active --quiet v2ray; then
        systemctl restart v2ray
      fi
    fi
  fi
  
  # Monitor CPU usage and adjust v2ray/xray priority dynamically
  if command -v bc >/dev/null 2>&1; then
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    
    # Find v2ray/xray PID
    if systemctl is-active --quiet xray; then
      V2RAY_PID=$(pgrep xray)
    elif systemctl is-active --quiet v2ray; then
      V2RAY_PID=$(pgrep v2ray)
    else
      V2RAY_PID=""
    fi
    
    if [ ! -z "$V2RAY_PID" ]; then
      if (( $(echo "$CPU_USAGE > 80.0" | bc -l) )); then
        # System under heavy load, adjust v2ray priority
        log "CPU usage high (${CPU_USAGE}%). Setting normal priority for v2ray/xray."
        renice -n 0 -p $V2RAY_PID  # Reset to normal priority under heavy load
      elif (( $(echo "$CPU_USAGE < 40.0" | bc -l) )); then
        # System has spare capacity, optimize v2ray
        log "CPU usage low (${CPU_USAGE}%). Setting high priority for v2ray/xray."
        renice -n -10 -p $V2RAY_PID  # Higher priority when system is not busy
      fi
    fi
  fi
  
  # Sleep for 5 minutes
  sleep 300
done
EOF

chmod +x /usr/local/bin/memory-management.sh
systemctl enable memory-management.service
systemctl start memory-management.service

########################################
# 9. Load and Persist BBR Congestion Control with Advanced Parameters
########################################
echo -e "${GREEN}Ensuring BBR congestion control is loaded with optimized parameters...${NC}"
# Check if BBR is active; note: if built into the kernel, modprobe may not be needed.
if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    modprobe tcp_bbr || true
    # Persist the module on boot
    if ! grep -q "^tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null; then
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi
fi

# Check kernel version for BBR v2 support
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
if awk "BEGIN {exit !($KERNEL_VERSION >= 5.15)}"; then
    echo -e "${GREEN}Kernel 5.15+ detected, enabling BBR v2 if available...${NC}"
    if modprobe tcp_bbr2 2>/dev/null; then
        echo "net.core.default_qdisc = fq" > /etc/sysctl.d/99-bbr2.conf
        echo "net.ipv4.tcp_congestion_control = bbr2" >> /etc/sysctl.d/99-bbr2.conf
        sysctl -p /etc/sysctl.d/99-bbr2.conf
        # Persist the module on boot
        if ! grep -q "^tcp_bbr2" /etc/modules-load.d/modules.conf 2>/dev/null; then
            echo "tcp_bbr2" >> /etc/modules-load.d/modules.conf
        fi
        # Optimize BBR parameters for better censorship resistance
        if [ -d "/sys/module/tcp_bbr2/parameters" ]; then
            echo 1 > /sys/module/tcp_bbr2/parameters/bbr_min_rtt_win_sec
        fi
        echo -e "${GREEN}BBR v2 enabled successfully with optimized parameters${NC}"
    else
        echo -e "${GREEN}BBR v2 module not available, staying with BBR v1${NC}"
        # Optimize BBR v1 parameters
        if [ -d "/sys/module/tcp_bbr/parameters" ]; then
            echo 1 > /sys/module/tcp_bbr/parameters/bbr_min_rtt_win_sec
        fi
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
# 11. Additional Performance Optimizations
########################################
echo -e "${GREEN}Applying additional performance optimizations...${NC}"

# Disable unnecessary services
for service in snapd lxcfs lxd ufw firewalld; do
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}Disabling unnecessary service: $service${NC}"
        systemctl stop $service
        systemctl disable $service
    fi
done

# Optimize IO scheduler for SSD if present
if [ -d "/sys/block" ]; then
    for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
        if [ -e "$disk" ]; then
            # Check if the disk is an SSD
            if [ -e "$disk/queue/rotational" ] && [ "$(cat $disk/queue/rotational)" -eq 0 ]; then
                echo -e "${GREEN}SSD detected at $(basename $disk), optimizing IO scheduler...${NC}"
                if grep -q "none" $disk/queue/scheduler; then
                    echo "none" > $disk/queue/scheduler
                elif grep -q "mq-deadline" $disk/queue/scheduler; then
                    echo "mq-deadline" > $disk/queue/scheduler
                elif grep -q "kyber" $disk/queue/scheduler; then
                    echo "kyber" > $disk/queue/scheduler
                fi
                # Optimize IO settings for SSD
                if [ -e "$disk/queue/read_ahead_kb" ]; then
                    echo 256 > $disk/queue/read_ahead_kb
                fi
                if [ -e "$disk/queue/nr_requests" ]; then
                    echo 256 > $disk/queue/nr_requests
                fi
            else
                # For HDDs, use deadline or mq-deadline
                if grep -q "mq-deadline" $disk/queue/scheduler; then
                    echo "mq-deadline" > $disk/queue/scheduler
                elif grep -q "deadline" $disk/queue/scheduler; then
                    echo "deadline" > $disk/queue/scheduler
                fi
                # Optimize read-ahead for HDDs
                if [ -e "$disk/queue/read_ahead_kb" ]; then
                    echo 1024 > $disk/queue/read_ahead_kb
                fi
            fi
        fi
    done
fi

# Optimize IRQ affinity for network cards with better distribution
if [ -d "/proc/irq" ]; then
    # Get the number of CPU cores
    NUM_CORES=$(nproc)
    
    # If we have multiple cores, distribute IRQs
    if [ "$NUM_CORES" -gt 1 ]; then
        echo -e "${GREEN}Optimizing IRQ affinity for network cards across $NUM_CORES cores...${NC}"
        
        # Find network interface IRQs
        IRQS=$(grep "$DEFAULT_NIC" /proc/interrupts | awk '{print $1}' | tr -d ':')
        CORE=0
        
        for irq in $IRQS; do
            if [ -d "/proc/irq/$irq" ]; then
                # Distribute IRQs across cores (round-robin)
                echo $CORE > /proc/irq/$irq/smp_affinity_list
                CORE=$(( (CORE + 1) % NUM_CORES ))
            fi
        done
    fi
fi

# TCP fragmentation removed as requested

########################################
# 12. Kernel Parameter Validation
########################################
echo -e "${GREEN}Validating kernel parameters...${NC}"

# Check for conntrack module
if ! lsmod | grep -q conntrack; then
    echo -e "${GREEN}Loading nf_conntrack module...${NC}"
    modprobe nf_conntrack || modprobe ip_conntrack || true
    echo "nf_conntrack" >> /etc/modules-load.d/modules.conf
fi

# Function to safely apply sysctl parameters
validate_sysctl() {
    local param=$1
    if sysctl -q "$param" &>/dev/null; then
        return 0
    else
        echo "Warning: Kernel parameter $param not available, removing from config"
        sed -i "/$param/d" /etc/sysctl.d/99-xray.conf
        return 1
    fi
}

# Validate key parameters
validate_sysctl "net.netfilter.nf_conntrack_max" || 
    validate_sysctl "net.ipv4.netfilter.ip_conntrack_max" || true
validate_sysctl "net.ipv4.tcp_fastopen" || true
validate_sysctl "net.ipv4.tcp_ecn" || true
validate_sysctl "net.core.default_qdisc" || true
validate_sysctl "net.ipv4.tcp_congestion_control" || true

########################################
# 13. Create Systemd Service for Network Optimizations
########################################
echo -e "${GREEN}Creating systemd service for network optimizations...${NC}"
cat > /etc/systemd/system/network-optimizations.service << EOF
[Unit]
Description=Network Interface Optimizations
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/optimize-network.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create the optimization script
cat > /usr/local/bin/optimize-network.sh << EOF
#!/bin/bash
# Network interface optimization script

# Get default interface
DEFAULT_NIC=\$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print \$5; exit}')
if [[ -z "\$DEFAULT_NIC" ]]; then
    DEFAULT_NIC="eth0"
fi

# Verify the interface exists
if ! ip link show "\$DEFAULT_NIC" >/dev/null 2>&1; then
    echo "Error: Network interface '\$DEFAULT_NIC' not found"
    exit 1
fi

# Enable offloading features
ethtool -K "\$DEFAULT_NIC" tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Set ring buffer sizes
ethtool -G "\$DEFAULT_NIC" rx 4096 tx 4096 2>/dev/null || true

# Adjust interrupt coalescence
ethtool -C "\$DEFAULT_NIC" adaptive-rx off adaptive-tx off rx-usecs 15 tx-usecs 15 2>/dev/null || true

# Increase transmit queue length
ip link set dev "\$DEFAULT_NIC" txqueuelen 10000 2>/dev/null || true

# Optimize IRQ affinity on multi-core systems
NUM_CORES=\$(nproc)
if [ "\$NUM_CORES" -gt 1 ]; then
    # Find network interface IRQs
    IRQS=\$(grep "\$DEFAULT_NIC" /proc/interrupts | awk '{print \$1}' | tr -d ':')
    CORE=0
    
    for irq in \$IRQS; do
        if [ -d "/proc/irq/\$irq" ]; then
            # Distribute IRQs across cores (round-robin)
            echo \$CORE > /proc/irq/\$irq/smp_affinity_list
            CORE=\$(( (CORE + 1) % NUM_CORES ))
        fi
    done
fi

exit 0
EOF

chmod +x /usr/local/bin/optimize-network.sh
systemctl enable network-optimizations.service

########################################
# 14. Xray/V2Ray Performance Optimizations
########################################
echo -e "${GREEN}Optimizing Xray/V2Ray for VLESS+REALITY...${NC}"

# Function to detect Xray/V2Ray installation
detect_v2ray_xray() {
    if [ -f /usr/local/bin/xray ] || [ -f /usr/bin/xray ]; then
        echo "xray"
    elif [ -f /usr/local/bin/v2ray ] || [ -f /usr/bin/v2ray ]; then
        echo "v2ray"
    else
        echo "none"
    fi
}

V2RAY_TYPE=$(detect_v2ray_xray)

if [ "$V2RAY_TYPE" != "none" ]; then
    echo -e "${GREEN}$V2RAY_TYPE detected, applying performance optimizations...${NC}"
    
    # Determine config file location
    if [ "$V2RAY_TYPE" = "xray" ]; then
        CONFIG_DIR="/usr/local/etc/xray"
        if [ ! -d "$CONFIG_DIR" ]; then
            CONFIG_DIR="/etc/xray"
        fi
        SERVICE_NAME="xray"
    else
        CONFIG_DIR="/usr/local/etc/v2ray"
        if [ ! -d "$CONFIG_DIR" ]; then
            CONFIG_DIR="/etc/v2ray"
        fi
        SERVICE_NAME="v2ray"
    fi
    
    # Create service override for performance - less aggressive than before
    mkdir -p /etc/systemd/system/${SERVICE_NAME}.service.d/
    cat > /etc/systemd/system/${SERVICE_NAME}.service.d/override.conf << EOF
[Service]
# Optimize process priority - balanced approach
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=50
IOSchedulingClass=best-effort
IOSchedulingPriority=0
# Optimize memory
MemoryDenyWriteExecute=no
# Optimize file descriptors for thousands of users
LimitNOFILE=1048576
EOF
    
    # Reload systemd and restart service
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME
    
    # Check for updates
    echo -e "${GREEN}Checking for $V2RAY_TYPE updates...${NC}"
    if [ "$V2RAY_TYPE" = "xray" ]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ check || true
    else
        bash -c "$(curl -L https://github.com/v2fly/fhs-install-v2ray/raw/master/install-release.sh)" @ check || true
    fi
    
    # Optimize process niceness - more balanced approach
    PID=$(pgrep $V2RAY_TYPE)
    if [ ! -z "$PID" ]; then
        echo -e "${GREEN}Setting $V2RAY_TYPE process priority...${NC}"
        renice -n -10 -p $PID  # Changed from -20 to -10 for better stability
        # Set IO priority (less aggressive)
        ionice -c 2 -n 0 -p $PID  # Changed from class 1 to class 2 for better stability
    fi
    
    # Check and optimize connection reuse in config
    if [ -d "$CONFIG_DIR" ]; then
        for config in "$CONFIG_DIR"/*.json; do
            if [ -f "$config" ]; then
                # Check if config has the deprecated connectionReuse setting
                if grep -q "connectionReuse" "$config"; then
                    echo -e "${GREEN}Removing deprecated connectionReuse setting from $config${NC}"
                    # Create backup
                    cp "$config" "$config.backup"
                    # Remove the deprecated setting
                    sed -i '/connectionReuse/d' "$config" || true
                fi
            fi
        done
    fi
else
    echo -e "${GREEN}Xray/V2Ray not detected. Skipping specific optimizations.${NC}"
fi
