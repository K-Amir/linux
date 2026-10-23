#!/usr/bin/env bash
# Hysteria 2 / QUIC UDP tuning and optional swap for Ubuntu/Debian.
# Does not change firewall rules, port hopping, NIC offloads, or TCP BBR.
# Safe to rerun. Does not restart services.
set -Eeuo pipefail

if (( EUID != 0 )); then
  echo 'Run as root: sudo bash hysteria2-optimize-fixed.sh' >&2
  exit 1
fi

for cmd in awk grep df findmnt sysctl swapon mkswap fallocate dd chmod rm \
           mkdir cp mv date; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

SYSCTL_FILE=/etc/sysctl.d/99-hysteria2.conf
OLD_SYSCTL_FILE=/etc/sysctl.d/99-xray.conf
SWAPFILE=/swapfile
STAMP=$(date +%Y%m%d-%H%M%S)
RAM_MB=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024; exit }' /proc/meminfo)

if [[ ! "$RAM_MB" =~ ^[0-9]+$ ]] || (( RAM_MB < 64 )); then
  echo 'Cannot determine available physical RAM.' >&2
  exit 1
fi

if (( RAM_MB <= 2500 )); then
  DEFAULT_SWAP_MB=2048
  DEFAULT_SOCKET_BUFFER=262144   # 256 KiB
  NETDEV_BACKLOG=4096
  CONNTRACK_TARGET=131072
else
  DEFAULT_SWAP_MB=1024
  DEFAULT_SOCKET_BUFFER=524288   # 512 KiB
  NETDEV_BACKLOG=8192
  CONNTRACK_TARGET=262144
fi

# Override e.g. SWAP_SIZE_MB=512, or disable with SWAP_SIZE_MB=0.
REQUESTED_SWAP_MB=${SWAP_SIZE_MB:-$DEFAULT_SWAP_MB}
if [[ ! "$REQUESTED_SWAP_MB" =~ ^[0-9]+$ ]]; then
  echo 'SWAP_SIZE_MB must be a nonnegative integer (MiB).' >&2
  exit 1
fi

echo "Physical RAM: ${RAM_MB} MiB"

# Only create a NEW swapfile if no swap exists anywhere. Never overwrite an
# existing /swapfile; it may contain data or be owned by another tool.
create_swapfile() {
  local size_mb=$1
  local fstype
  fstype=$(findmnt -n -o FSTYPE -T / 2>/dev/null || true)

  if [[ "$fstype" == btrfs ]]; then
    if command -v btrfs >/dev/null 2>&1; then
      echo 'Btrfs detected; using btrfs filesystem mkswapfile.'
      if ! btrfs filesystem mkswapfile --size "${size_mb}m" "$SWAPFILE"; then
        rm -f -- "$SWAPFILE"
        return 1
      fi
    else
      echo 'Btrfs needs btrfs-progs for safe swapfile creation. Skipping.' >&2
      return 1
    fi
  else
    if ! fallocate -l "${size_mb}M" "$SWAPFILE" 2>/dev/null; then
      rm -f -- "$SWAPFILE"
      echo 'fallocate failed; attempting fully allocated dd fallback.'
      if ! dd if=/dev/zero of="$SWAPFILE" bs=1M count="$size_mb" \
              conv=fsync status=none; then
        rm -f -- "$SWAPFILE"
        return 1
      fi
    fi
    chmod 600 "$SWAPFILE"
    if ! mkswap "$SWAPFILE" >/dev/null; then
      rm -f -- "$SWAPFILE"
      return 1
    fi
  fi

  chmod 600 "$SWAPFILE"
  if ! swapon "$SWAPFILE"; then
    echo 'swapon failed: filesystem, quota or virtualization may disallow swap.' >&2
    rm -f -- "$SWAPFILE"
    return 1
  fi

  if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
