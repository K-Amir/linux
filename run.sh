#!/bin/bash

# Print colored output
GREEN='\033[0;32m'
NC='\033[0m' # No Color
echo -e "${GREEN}Starting optimization...${NC}"

# Update system and install minimal dependencies
echo -e "${GREEN}Installing essential dependencies...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget unzip

# Remove unnecessary services
echo -e "${GREEN}Removing unnecessary services...${NC}"
systemctl disable apache2 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
systemctl disable mysql 2>/dev/null || true
systemctl disable postfix 2>/dev/null || true
apt-get autoremove -y

# Configure swap with more conservative settings
echo -e "${GREEN}Setting up optimized swap...${NC}"
swapoff -a
dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
echo 'vm.swappiness=30' | tee -a /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' | tee -a /etc/sysctl.conf

# Optimize system limits with safety margins
echo -e "${GREEN}Configuring system limits...${NC}"
cat > /etc/security/limits.conf << EOF
* soft nofile 32768
* hard nofile 32768
* soft nproc 16384
* hard nproc 16384
root soft nofile 32768
root hard nofile 32768
EOF

# Optimize sysctl parameters with stability focus
echo -e "${GREEN}Optimizing network parameters...${NC}"
cat > /etc/sysctl.conf << EOF
# Maximum number of open files
fs.file-max = 32768
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 16384

# Network optimization with stability focus
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.core.rmem_max = 6291456
net.core.wmem_max = 6291456
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456
net.ipv4.tcp_mem = 6291456 6291456 6291456
net.ipv4.udp_mem = 6291456 6291456 6291456

# TCP optimization with safety margins
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_orphan_retries = 2

# Connection tracking with conservative limits
net.netfilter.nf_conntrack_max = 16384
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 60

# BBR configuration
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Memory optimization with stability focus
vm.overcommit_memory = 0
vm.min_free_kbytes = 65536
net.ipv4.tcp_moderate_rcvbuf = 1
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10

# Additional stability tweaks
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_max_orphans = 8192
net.ipv4.tcp_slow_start_after_idle = 0
EOF

# Apply sysctl settings
sysctl -p

# Enable BBR
if ! lsmod | grep -q bbr; then
    modprobe tcp_bbr
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
fi

# Clean up zombie processes
echo -e "${GREEN}Cleaning up processes...${NC}"
kill -9 $(ps -A -ostat,ppid,pid,cmd | grep -e '^[Zz]' | awk '{print $3}') 2>/dev/null || true

# Set up gentle memory cleanup
cat > /etc/cron.hourly/ram-cleanup << EOF
#!/bin/bash
if [ \$(free | awk '/^Mem/ {print int(\$3/\$2 * 100)}') -gt 85 ]; then
    sync
    echo 1 > /proc/sys/vm/drop_caches
fi
EOF
chmod +x /etc/cron.hourly/ram-cleanup

# Optimize network interface with safe settings
ethtool -K eth0 tso on gso on gro on 2>/dev/null || true

echo -e "${GREEN}Optimization complete!${NC}"
echo -e "${GREEN}Reboot your system to apply all changes.${NC}"
