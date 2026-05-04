#!/usr/bin/env bash

install_fedora_power_management() {
  section "Fedora-native power management"
  log "Fedora 44 uses Fedora-native tuned/tuned-ppd for power profiles."
  log "This script intentionally does not install TLP because TLP conflicts with tuned-ppd on newer Fedora releases."
  log "GNOME/KDE power profiles should continue working through tuned-ppd."

  run dnf install -y tuned tuned-ppd
  run systemctl enable --now tuned
  run_tolerate tuned-adm active
  run_tolerate tuned-adm recommend
}

write_thinkpad_threshold_script() {
  local path="/usr/local/sbin/thinkpad-battery-thresholds"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write executable threshold helper to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for battery in /sys/class/power_supply/BAT*; do
  [ -d "$battery" ] || continue

  start_threshold="$battery/charge_control_start_threshold"
  end_threshold="$battery/charge_control_end_threshold"

  if [ -w "$start_threshold" ]; then
    printf '%s\n' 75 > "$start_threshold"
  fi

  if [ -w "$end_threshold" ]; then
    printf '%s\n' 85 > "$end_threshold"
  fi
done
EOF
  run chmod +x "$path"
}

write_thinkpad_threshold_service() {
  local path="/etc/systemd/system/thinkpad-battery-thresholds.service"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write systemd service to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
[Unit]
Description=Set ThinkPad battery charge thresholds
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/thinkpad-battery-thresholds

[Install]
WantedBy=multi-user.target
EOF
}

configure_thinkpad_battery_thresholds() {
  section "ThinkPad battery charge thresholds without TLP"
  if ! confirm "Configure ThinkPad battery charge thresholds via /sys without TLP?"; then
    log "ThinkPad battery charge threshold setup skipped."
    return 0
  fi

  if ! compgen -G "/sys/class/power_supply/BAT*/charge_control_start_threshold" >/dev/null \
    && ! compgen -G "/sys/class/power_supply/BAT*/charge_control_end_threshold" >/dev/null; then
    log "Kernel/firmware does not expose charge threshold controls under /sys/class/power_supply/BAT*. Skipping safely."
    return 0
  fi

  write_thinkpad_threshold_script
  write_thinkpad_threshold_service
  run systemctl daemon-reload
  run systemctl enable --now thinkpad-battery-thresholds.service
  run_tolerate bash -c 'cat /sys/class/power_supply/BAT*/charge_control_*_threshold'
}

run_power_module() {
  install_fedora_power_management
  configure_thinkpad_battery_thresholds
}
