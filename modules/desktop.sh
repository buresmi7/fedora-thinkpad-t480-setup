#!/usr/bin/env bash

setup_gnome_touchpad() {
  section "GNOME touchpad settings"
  if ! confirm "Apply GNOME touchpad settings for user ${REAL_USER:-unknown}?"; then
    log "GNOME touchpad settings skipped."
    return 0
  fi

  run_as_real_user gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
  run_as_real_user gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
  run_as_real_user gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false
}

install_temperature_indicator() {
  local detected_uuid
  local freon_uuid="freon@UshakovVasilii_Github.yahoo.com"

  if ! confirm "Install GNOME top-bar CPU temperature indicator?"; then
    log "Temperature indicator skipped."
    return 0
  fi

  section "Installing CPU temperature indicator"
  run dnf install -y lm_sensors gnome-shell-extension-freon

  log "Running sensors-detect. Default answers are usually safe."
  run_tolerate sensors-detect

  log "Available sensors:"
  run_tolerate sensors

  detected_uuid="$(rpm -ql gnome-shell-extension-freon 2>/dev/null | awk -F/ '/\/usr\/share\/gnome-shell\/extensions\/freon@/ {print $NF; exit}' || true)"
  if [ -n "$detected_uuid" ]; then
    freon_uuid="$detected_uuid"
  fi

  log "Freon GNOME Shell extension UUID: $freon_uuid"
  if [ -n "$REAL_USER" ]; then
    run_as_real_user gnome-extensions enable "$freon_uuid"
  else
    log "No non-root SUDO_USER detected; enable Freon manually:"
    log "  gnome-extensions enable '$freon_uuid'"
  fi
}

install_external_monitor_brightness() {
  if ! confirm "Install external monitor brightness control via DDC/CI?"; then
    log "External monitor brightness control skipped."
    return 0
  fi

  section "Installing DDC/CI monitor brightness tools"
  run dnf install -y ddcutil i2c-tools
  run_tolerate modprobe i2c-dev

  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    log "No non-root SUDO_USER detected; skipping i2c group membership."
  elif [ "$DRY_RUN" -eq 1 ]; then
    log "Would add $REAL_USER to i2c group."
  else
    run groupadd -f i2c
    run usermod -aG i2c "$REAL_USER"
  fi

  log "Testing monitor detection. Some monitors require DDC/CI to be enabled in the monitor OSD menu."
  run_tolerate ddcutil detect
}

run_desktop_module() {
  setup_gnome_touchpad
  install_temperature_indicator
  install_external_monitor_brightness
}
