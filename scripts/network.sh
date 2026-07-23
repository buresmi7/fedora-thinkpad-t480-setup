#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

: "${PREFER_WIRED_IF:=}"
: "${PREFER_WIFI_IF:=}"
: "${PREFER_WIRED_CONN:=}"
: "${PREFER_WIFI_CONN:=}"

systemd_env_value() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

connection_exists() {
  nmcli -t -f NAME connection show | grep -Fxq "$1"
}

first_device_by_type() {
  nmcli -t -f DEVICE,TYPE device status |
    awk -F: -v type="$1" '$2 == type { print $1; exit }'
}

first_connected_device_by_type() {
  nmcli -t -f DEVICE,TYPE,STATE device status |
    awk -F: -v type="$1" '$2 == type && $3 == "connected" { print $1; exit }'
}

first_connection_by_type() {
  nmcli -t -f NAME,TYPE connection show |
    awk -F: -v type="$1" '$2 == type { print $1; exit }'
}

active_connection_for_device() {
  nmcli -t -f NAME,DEVICE connection show --active |
    awk -F: -v dev="$1" '$2 == dev { print $1; exit }'
}

install_prefer_wired_service() {
  local env_file
  local wired_conn
  local wired_if
  local wifi_conn
  local wifi_if
  local user_bin
  local user_unit

  if [ -z "$REAL_USER" ] || [ -z "$REAL_HOME" ]; then
    log "No target desktop user detected; skipping network preference service."
    return 1
  fi

  if ! confirm "Install user service that disables Wi-Fi while Ethernet is connected?"; then
    log "Network preference service skipped."
    return 0
  fi

  section "Installing wired-over-Wi-Fi preference service"
  user_bin="$REAL_HOME/.local/bin/prefer-wired-network"
  user_unit="$REAL_HOME/.config/systemd/user/prefer-wired-network.service"
  env_file="$REAL_HOME/.config/prefer-wired-network.env"

  wired_if="${PREFER_WIRED_IF:-$(first_connected_device_by_type ethernet)}"
  wired_if="${wired_if:-$(first_device_by_type ethernet)}"
  wifi_if="${PREFER_WIFI_IF:-$(first_device_by_type wifi)}"
  wifi_conn="${PREFER_WIFI_CONN:-$(first_connection_by_type 802-11-wireless)}"

  if [ -z "$wired_if" ] || [ -z "$wifi_if" ]; then
    log "Could not detect both wired and Wi-Fi devices."
    log "Override with PREFER_WIRED_IF and PREFER_WIFI_IF."
    return 1
  fi

  run install -D -m 0755 "$PROJECT_DIR/assets/prefer-wired-network" "$user_bin"
  run install -D -m 0644 "$PROJECT_DIR/assets/prefer-wired-network.service" "$user_unit"
  run chown "$REAL_USER:" "$user_bin" "$user_unit"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would write $env_file"
  else
    install -d -m 0755 -o "$REAL_USER" -g "$(id -gn "$REAL_USER")" "$(dirname "$env_file")"
    {
      printf 'PREFER_WIRED_IF="%s"\n' "$(systemd_env_value "$wired_if")"
      printf 'PREFER_WIFI_IF="%s"\n' "$(systemd_env_value "$wifi_if")"
      printf 'PREFER_WIFI_CONN="%s"\n' "$(systemd_env_value "$wifi_conn")"
    } > "$env_file"
    chown "$REAL_USER:" "$env_file"
    chmod 0600 "$env_file"
  fi

  wired_conn="${PREFER_WIRED_CONN:-$(active_connection_for_device "$wired_if")}"
  wired_conn="${wired_conn:-$(first_connection_by_type 802-3-ethernet)}"
  if [ -n "$wired_conn" ] && connection_exists "$wired_conn"; then
    run nmcli connection modify "$wired_conn" \
      connection.autoconnect yes \
      connection.autoconnect-priority 100 \
      ipv4.route-metric 100 \
      ipv6.route-metric 100
  else
    log "Wired connection profile not found for device: $wired_if"
  fi

  if [ -n "$wifi_conn" ] && connection_exists "$wifi_conn"; then
    run nmcli connection modify "$wifi_conn" \
      connection.autoconnect yes \
      connection.autoconnect-priority 0 \
      ipv4.route-metric 600 \
      ipv6.route-metric 600
  else
    log "Wi-Fi connection profile not found; Wi-Fi will use device autoconnect."
  fi

  run_as_real_user systemctl --user daemon-reload
  run_as_real_user systemctl --user enable --now prefer-wired-network.service

  log "Check status with:"
  log "  systemctl --user status prefer-wired-network.service"
}

run_network_module() {
  install_prefer_wired_service
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main network run_network_module "$@"
fi
