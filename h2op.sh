      echo 'Could not allocate swapfile (check filesystem). Skipping swap.' >&2
    else
      chmod 600 "$SWAPFILE"
      mkswap "$SWAPFILE" >/dev/null
      if swapon "$SWAPFILE"; then
        if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+' /etc/fstab; then
          echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        echo 'Swap activated and made persistent.'
      else
        echo 'WARNING: could not activate swapfile; check filesystem support.' >&2
        rm -f "$SWAPFILE"
      fi
    fi
  fi
fi

# The user's old script generated this particular Xray tuning file.
# Disable it only if its identifying comments match. Otherwise don't touch it.
if [[ -f "$LEGACY_FILE" ]]; then
  if grep -Fq '# Optimized for VLESS+Reality in censored environments' "$LEGACY_FILE" \
      && grep -Fq '# Auto-generated for' "$LEGACY_FILE"; then
    mv "$LEGACY_FILE" "${LEGACY_FILE}.disabled-${STAMP}"
    echo "Disabled old Xray sysctl file (backed up with .disabled-${STAMP} suffix)."
  else
    echo "WARNING: $LEGACY_FILE exists but was not recognized; left unchanged." >&2
    echo 'Its parameters may conflict with the Hysteria 2 tuning file.' >&2
  fi
fi

# Raising buffer MAX allows the QUIC implementation to request larger UDP
# buffers. Keeping DEFAULT lower avoids gratuitous buffer budgets for every
# new socket. Bigger is not always better for latency or small VPSs.
if (( TOTAL_RAM_MB <= 2500 )); then
  DEFAULT_BUFFER=262144      # 256 KiB
  NETDEV_BACKLOG=4096
else
  DEFAULT_BUFFER=524288      # 512 KiB
  NETDEV_BACKLOG=8192
fi

mkdir -p "$SYSCTL_DIR"
if [[ -f "$TUNING_FILE" ]]; then
  cp -a "$TUNING_FILE" "${TUNING_FILE}.backup-${STAMP}"
fi
cat > "$TUNING_FILE" <<EOF
# Hysteria 2 / QUIC: Linux UDP + resource settings
# Generated for ${TOTAL_RAM_MB} MiB RAM. Intended for UDP 443 and optional hopping.

# Overall open-file ceiling (systemd services have their own NOFILE limit).
fs.file-max = 1000000

# QUIC / UDP socket buffers: Hysteria recommends a 16 MiB maximum.
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = ${DEFAULT_BUFFER}
net.core.wmem_default = ${DEFAULT_BUFFER}

# Queue for bursts of inbound packets; 65536 usually adds unnecessary queueing.
net.core.netdev_max_backlog = ${NETDEV_BACKLOG}

# Keep per-UDP-socket minimum reasonably small.
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Swap is a safety net, not a substitute for physical memory.
vm.swappiness = 10
EOF

# Optional: on a server using DNAT/REDIRECT for port hopping, conntrack may
# hold many concurrent UDP mappings. Never lower an existing higher limit.
CONNTRACK_PATH=/proc/sys/net/netfilter/nf_conntrack_max
if [[ -r "$CONNTRACK_PATH" ]]; then
  if (( TOTAL_RAM_MB <= 2500 )); then
    CONNTRACK_TARGET=131072
  else
    CONNTRACK_TARGET=262144
  fi
  CONNTRACK_CURRENT=$(cat "$CONNTRACK_PATH")
  if [[ "$CONNTRACK_CURRENT" =~ ^[0-9]+$ ]] && (( CONNTRACK_CURRENT < CONNTRACK_TARGET )); then
    cat >> "$TUNING_FILE" <<EOF

# Helps when many client UDP port-hop flows are handled with NAT.
net.netfilter.nf_conntrack_max = ${CONNTRACK_TARGET}
EOF
  fi
fi

# Apply only this file: don't reapply old or unrelated sysctl configurations.
sysctl -p "$TUNING_FILE"

# A Hysteria process run by systemd also needs a sufficiently high NOFILE
# soft/hard limit. Create a separate drop-in only for existing relevant units.
# No immediate restart is performed, to avoid dropping SSH/proxy sessions.
if command -v systemctl >/dev/null 2>&1; then
  UNIT_CHANGED=0
  for UNIT in x-ui.service xray.service hysteria-server.service hysteria.service; do
    if [[ "$(systemctl show -p LoadState --value "$UNIT" 2>/dev/null || true)" == loaded ]]; then
      DROPIN_DIR="/etc/systemd/system/${UNIT}.d"
      mkdir -p "$DROPIN_DIR"
      cat > "${DROPIN_DIR}/zz-hysteria2-nofile.conf" <<'EOF'
[Service]
LimitNOFILE=131072
EOF
      echo "Configured LimitNOFILE=131072 for $UNIT (applies after its next restart)."
      UNIT_CHANGED=1
    fi
  done
  if (( UNIT_CHANGED )); then
    systemctl daemon-reload
  fi
fi

echo
echo 'Hysteria 2 kernel tuning complete.'
echo "Tuning file: ${TUNING_FILE}"
echo 'Effective UDP socket maxima:'
sysctl net.core.rmem_max net.core.wmem_max net.core.netdev_max_backlog vm.swappiness
echo 'Swap status:'
swapon --show || true
echo
echo 'No Hysteria/3x-ui service was restarted. No firewall rules were changed.'
echo 'If the old Xray script was previously applied, reboot during a maintenance'
echo 'window to clear unrelated old live TCP settings that are no longer persistent.'
