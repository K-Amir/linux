#!/bin/bash

#----------------------------------------------------
#  COMPLETE OPTIMIZATION SCRIPT FOR XRAY VLESS+REALITY
#  - Enhanced connection stability
#  - Full system optimization
#  - IRQ and CPU optimizations
#  - Memory management
#----------------------------------------------------

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting complete Xray optimization...${NC}"

#-----------------------------------------------
# 1. Detect default network interface
#-----------------------------------------------
DEFAULT_NIC=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
if [[ -z "$DEFAULT_NIC" ]]; then
    echo -e "${GREEN}Could not detect default interface. Falling back to 'eth0'...${NC}"
    DEFAULT_NIC="eth0"
fi

#-----------------------------------------------
# 2. Install essential packages
#-----------------------------------------------
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip ethtool haveged irqbalance

#-----------------------------------------------
# 3. Enhanced sysctl configurations
#-----------------------------------------------
cat > /etc/sysctl.d/99-xray-complete.conf << EOF
# System limits
fs.file-max = 65535
fs.inotify.max_user_instances = 4096
fs.inotify.max_user_watches = 262144

# TCP optimization for stability and performance
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
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
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries1 = 5
net.ipv4.tcp_retries2 = 15
net.ipv4.ip_local_port_range = 1024 65535

# Aggressive TCP keepalive for connection persistence
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# Extended connection tracking
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Additional latency optimizations
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_frto = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_adv_win_scale = 2
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.route.flush = 1
net.ipv4.udp_early_demux = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.core.busy_poll = 50
net.core.busy_read = 50
net.ipv4.tcp_challenge_ack_limit = 1000
net.ipv4.tcp_limit_output_bytes = 262144

# Memory optimization
vm.swappiness = 30
vm.vfs_cache_pressure = 70
vm.min_free_kbytes = 65536
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 1500

# Additional TCP optimizations
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_mem = 786432 1048576 1572864

# IPv6 optimizations
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2

# Additional IPv6 latency optimizations
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.all.router_solicitations = 0
net.ipv6.conf.default.router_solicitations = 0
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.default.use_tempaddr = 0
net.ipv6.route.max_size = 32768
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
net.ipv6.neigh.default.gc_interval = 30
net.ipv6.neigh.default.gc_stale_time = 60
net.ipv6.bindv6only = 0
net.ipv6.mld_max_msf = 64
net.ipv6.ip6frag_time = 60
net.ipv6.ip6frag_low_thresh = 196608
net.ipv6.ip6frag_high_thresh = 262144

# Network queue and buffer optimizations
net.core.dev_weight = 32
net.core.netdev_budget = 200
net.core.netdev_budget_usecs = 4000

# Additional memory optimizations
vm.max_map_count = 131072
vm.overcommit_memory = 1
vm.page-cluster = 2
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-xray-complete.conf

#-----------------------------------------------
# 4. Network interface optimization
#-----------------------------------------------
# Enable offloading features
ethtool -K "${DEFAULT_NIC}" tso on gso on gro on 2>/dev/null || true
# Set ring buffer sizes
ethtool -G "${DEFAULT_NIC}" rx 4096 tx 4096 2>/dev/null || true

#-----------------------------------------------
# 5. System limits for Xray
#-----------------------------------------------
cat > /etc/security/limits.d/99-xray.conf << EOF
* soft     nproc          65535
* hard     nproc          65535
* soft     nofile         1000000
* hard     nofile         1000000
root soft     nproc          65535
root hard     nproc          65535
root soft     nofile         1000000
root hard     nofile         1000000
EOF

#-----------------------------------------------
# 6. Optimize IRQ balance for network card
#-----------------------------------------------
if [ -f /etc/default/irqbalance ]; then
    sed -i 's/#IRQBALANCE_BANNED_CPUS=/IRQBALANCE_BANNED_CPUS=/' /etc/default/irqbalance
    systemctl restart irqbalance
fi

#-----------------------------------------------
# 7. Memory management
#-----------------------------------------------
cat > /etc/cron.hourly/memory-management << 'EOF'
#!/bin/bash
USED=$(free | awk '/^Mem/ {print int($3/$2 * 100)}')
if [ "$USED" -gt 90 ]; then
    sync
    echo 1 > /proc/sys/vm/drop_caches
    echo 1 > /proc/sys/vm/compact_memory
fi
EOF
chmod +x /etc/cron.hourly/memory-management

#-----------------------------------------------
# 8. Load and persist BBR
#-----------------------------------------------
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

#-----------------------------------------------
# 9. Network scheduler optimization (Fixed)
#-----------------------------------------------
if [ -f /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_cpus ]; then
    # Get number of CPU cores
    NUM_CORES=$(nproc)
    
    # For 1-2 cores, use a more conservative mask
    if [ "$NUM_CORES" -eq 1 ]; then
        CPU_MASK="1"
    else
        CPU_MASK="3"  # Use both cores for 2-core system
    fi
    
    # Apply RPS/XPS settings safely
    echo "$CPU_MASK" > /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_cpus 2>/dev/null || echo "Warning: Could not set RPS CPU mask"
    echo "$CPU_MASK" > /sys/class/net/${DEFAULT_NIC}/queues/tx-0/xps_cpus 2>/dev/null || echo "Warning: Could not set XPS CPU mask"
    
    # Set flow entries (using smaller values for low memory)
    echo 2048 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || echo "Warning: Could not set flow entries"
    echo 2048 > /sys/class/net/${DEFAULT_NIC}/queues/rx-0/rps_flow_cnt 2>/dev/null || echo "Warning: Could not set flow count"
fi

#-----------------------------------------------
# 10. CPU Frequency Scaling Optimization
#-----------------------------------------------
if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
    # Set CPU governor to performance
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu" 2>/dev/null || true
    done
fi

#-----------------------------------------------
# 11. Additional Network Interface Optimizations
#-----------------------------------------------
# Disable network interface power saving
ethtool -s ${DEFAULT_NIC} wol d 2>/dev/null || true
ethtool --set-eee ${DEFAULT_NIC} eee off 2>/dev/null || true

# Increase network interface transmit queue length
ip link set dev ${DEFAULT_NIC} txqueuelen 10000 2>/dev/null || true

# Disable TCP slow start after idle
ethtool -K ${DEFAULT_NIC} sg on 2>/dev/null || true
ethtool -K ${DEFAULT_NIC} tso on 2>/dev/null || true
ethtool -K ${DEFAULT_NIC} ufo on 2>/dev/null || true

# Additional latency optimizations for network interface
# Disable interrupt coalescing
ethtool -C ${DEFAULT_NIC} rx-usecs 0 rx-frames 0 2>/dev/null || true
# Disable adaptive interrupt coalescing
ethtool -C ${DEFAULT_NIC} adaptive-rx off 2>/dev/null || true
# Set interrupt coalescing parameters for low latency
ethtool -C ${DEFAULT_NIC} rx-usecs 0 tx-usecs 0 2>/dev/null || true

# Optimize for low latency using tc
tc qdisc add dev ${DEFAULT_NIC} root fq_codel flows 32768 quantum 300 noecn 2>/dev/null || \
tc qdisc change dev ${DEFAULT_NIC} root fq_codel flows 32768 quantum 300 noecn 2>/dev/null || true

echo -e "${GREEN}Complete optimization finished!${NC}"
echo -e "${GREEN}Please reboot your system to apply all changes.${NC}"
