#!/bin/bash

#----------------------------------------------------
#  GAMING-OPTIMIZED SCRIPT FOR VMESS+TLS
#  - Ultra-low latency optimization
#  - Anti-censorship enhancements
#  - Gaming traffic prioritization
#  - Connection stability improvements
#----------------------------------------------------

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting Vmess+TLS gaming optimization...${NC}"

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
    curl wget unzip ethtool haveged irqbalance \
    iptables-persistent

#-----------------------------------------------
# 3. Gaming-optimized sysctl configurations
#-----------------------------------------------
cat > /etc/sysctl.d/99-vmess-gaming.conf << 'EOF'
# System limits
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# Ultra-low latency TCP optimization
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 16777216
net.ipv4.tcp_wmem = 4096 1048576 16777216
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Gaming-focused TCP optimization
# Enhanced TCP stability and mobile optimization
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# Ultra-aggressive gaming keepalive
net.ipv4.tcp_keepalive_time = 5
net.ipv4.tcp_keepalive_intvl = 1
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_retries1 = 1
net.ipv4.tcp_retries2 = 2

# Enhanced gaming connection tracking
net.netfilter.nf_conntrack_max = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 5
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 5
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 5

# Direct TLS optimization (no WebSocket)
net.core.busy_poll = 10
net.core.busy_read = 10
net.ipv4.tcp_notsent_lowat = 4096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_base_mss = 1024
net.ipv4.tcp_probe_interval = 0.1
net.ipv4.tcp_probe_threshold = 1
net.ipv4.tcp_tso_win_divisor = 1

# BBR and advanced TCP features
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_early_retrans = 1
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_thin_dupack = 1
net.ipv4.tcp_thin_linear_timeouts = 1

# Low latency optimizations
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
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_moderate_rcvbuf = 1

# Memory optimization
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 131072
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 300
vm.max_map_count = 131072
vm.overcommit_memory = 1
vm.page-cluster = 2

# Network queue optimization
net.core.dev_weight = 32
net.core.netdev_budget = 200
net.core.netdev_budget_usecs = 4000

# IPv6 configuration
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
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-xray-complete.conf

#-----------------------------------------------
# 4. Network interface optimization
#-----------------------------------------------
# Enable optimized network offloading
ethtool -K ${DEFAULT_NIC} tso on gso on gro on sg on tx on rx on 2>/dev/null || true

# Optimize ring buffer sizes for better performance
ethtool -G ${DEFAULT_NIC} rx 4096 tx 4096 2>/dev/null || true

# Set interrupt coalescence for better stability
ethtool -C ${DEFAULT_NIC} adaptive-rx on adaptive-tx on rx-usecs 100 tx-usecs 100 2>/dev/null || true

# Increase queue length for better performance
ip link set dev ${DEFAULT_NIC} txqueuelen 20000 2>/dev/null || true

# Use fq_codel with optimized parameters for better throughput and lower latency
tc qdisc add dev ${DEFAULT_NIC} root fq_codel flows 32768 quantum 1514 target 5ms interval 100ms noecn 2>/dev/null || \
tc qdisc change dev ${DEFAULT_NIC} root fq_codel flows 32768 quantum 1514 target 5ms interval 100ms noecn 2>/dev/null || true

#-----------------------------------------------
# 5. System limits for Xray
#-----------------------------------------------
cat > /etc/security/limits.d/99-xray.conf << 'EOF'
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

#-----------------------------------------------
# 11. Gaming-specific network optimizations
#-----------------------------------------------
# Optimize NIC interrupt handling
for i in $(ls -d /sys/class/net/${DEFAULT_NIC}/queues/rx-*/rps_cpus 2>/dev/null); do
    echo "f" > $i 2>/dev/null || true
done

# Set maximum network interface transmit queue length
ip link set dev ${DEFAULT_NIC} txqueuelen 40000 2>/dev/null || true

# Optimize NIC parameters for gaming
ethtool -G ${DEFAULT_NIC} rx 4096 tx 4096 2>/dev/null || true
ethtool -K ${DEFAULT_NIC} tso off gso off gro off lro off rx off tx off 2>/dev/null || true
ethtool -C ${DEFAULT_NIC} rx-usecs 0 rx-frames 0 tx-usecs 0 tx-frames 0 2>/dev/null || true
ethtool -A ${DEFAULT_NIC} autoneg off rx off tx off 2>/dev/null || true

# Gaming-optimized traffic control
tc qdisc del dev ${DEFAULT_NIC} root 2>/dev/null || true
tc qdisc add dev ${DEFAULT_NIC} root fq flow_limit 500 quantum 1514 initial_quantum 15140 maxrate 2gbit 2>/dev/null || true

#-----------------------------------------------
# 12. CPU isolation for network processing
#-----------------------------------------------
if [ $(nproc) -gt 2 ]; then
    # Reserve last CPU core for network processing
    echo 2 > /proc/irq/default_smp_affinity 2>/dev/null || true
    
    # Set IRQ affinity for network card
    for irq in $(grep ${DEFAULT_NIC} /proc/interrupts | cut -d: -f1); do
        echo 2 > /proc/irq/$irq/smp_affinity 2>/dev/null || true
    done
fi

#-----------------------------------------------
# 13. Memory optimization for gaming
#-----------------------------------------------
echo 0 > /proc/sys/vm/zone_reclaim_mode 2>/dev/null || true
echo 0 > /proc/sys/kernel/numa_balancing 2>/dev/null || true
echo 100 > /proc/sys/vm/swappiness 2>/dev/null || true

# Disable any unnecessary services
systemctl stop snapd 2>/dev/null || true
systemctl disable snapd 2>/dev/null || true
systemctl stop packagekit 2>/dev/null || true
systemctl disable packagekit 2>/dev/null || true

echo -e "${GREEN}Ultra-low latency gaming optimization complete!${NC}"
echo -e "${GREEN}Please reboot your system to apply all changes.${NC}"
echo -e "${GREEN}Recommendations for lowest latency:${NC}"
echo -e "1. Use direct TLS without WebSocket for minimal overhead"
echo -e "2. Choose a server with the lowest ping to your gaming servers"
echo -e "3. Consider using anycast IP for automatic server selection"
echo -e "4. Monitor your connection with 'mtr' or 'ping' to verify latency"
