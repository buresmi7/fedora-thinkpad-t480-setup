#!/usr/bin/env bash

readonly T480_FINGERPRINT_USB_ID="06cb:009a"
readonly PYTHON_VALIDITY_COPR="sneexy/python-validity"

fingerprint_usb_lines() {
  lsusb | grep -Ei 'finger|synaptics|06cb:009a' || true
}

write_fingerprint_resume_hook() {
  local path="/usr/lib/systemd/system-sleep/t480-fingerprint-resume"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write fingerprint resume hook to $path"
    return 0
  fi

  run mkdir -p /usr/lib/systemd/system-sleep
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -u

if [ "${1:-}" != "post" ]; then
  exit 0
fi

logger -t t480-fingerprint-resume "post-resume recovery started"

# Suspend/resume workaround for the T480 Synaptics 06cb:009a reader.
# systemd-sleep on Fedora 44 runs hooks from /usr/lib/systemd/system-sleep
# while user.slice is still frozen. Doing recovery here prevents GNOME Shell
# from building the unlock prompt before open-fprintd/python-validity are ready.
for _ in 1 2 3 4 5; do
  if lsusb -d 06cb:009a >/dev/null 2>&1; then
    logger -t t480-fingerprint-resume "fingerprint USB device is present"
    break
  fi
  sleep 1
done

udevadm settle --timeout=5 >/dev/null 2>&1 || true
systemctl restart python3-validity.service >/dev/null 2>&1 || true
sleep 1
systemctl restart open-fprintd.service >/dev/null 2>&1 || true
sleep 1
target_user="$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"
if [ -n "$target_user" ]; then
  fprintd-list "$target_user" >/dev/null 2>&1 || true
fi

logger -t t480-fingerprint-resume "post-resume recovery finished"
EOF
  run chmod +x "$path"
  run_tolerate chown root:root /usr/lib/systemd/system-sleep "$path"
  if command -v restorecon >/dev/null 2>&1; then
    run_tolerate restorecon -F /usr/lib/systemd/system-sleep "$path"
  fi
}

enable_open_fprintd_sleep_units() {
  local unit

  if systemctl cat open-fprintd-suspend.service >/dev/null 2>&1; then
    run systemctl enable open-fprintd-suspend.service
  else
    log "open-fprintd-suspend.service not found; continuing with the generic resume hook."
  fi

  # These services run after user.slice thaws. On this T480 they race with the
  # GNOME lock prompt, so recovery is handled by the synchronous system-sleep
  # hook instead.
  for unit in open-fprintd-resume.service python3-validity-restart-after-resume.service open-fprintd-restart-after-resume.service; do
    if systemctl cat "$unit" >/dev/null 2>&1; then
      log "Disabling $unit; fingerprint resume is handled by /usr/lib/systemd/system-sleep/t480-fingerprint-resume."
      run_tolerate systemctl disable "$unit"
    fi
  done
}

prepare_validity_fingerprint_reader() {
  if ! confirm "Prepare the Synaptics validity fingerprint reader firmware/calibration? This may reset stored fingerprint data."; then
    log "Validity fingerprint reader preparation skipped."
    return 0
  fi

  run_tolerate touch /usr/share/python-validity/backoff /usr/share/python-validity/calib-data.bin
  run_tolerate validity-sensors-firmware
  run_tolerate bash -c 'if [ -r /usr/share/python-validity/playground/factory-reset.py ]; then python3 /usr/share/python-validity/playground/factory-reset.py; else echo "factory-reset.py not found; skipping."; fi'
  run_tolerate bash -c 'chmod 0755 /usr/share/python-validity/*_lenovo_mis_qm.xpfwext 2>/dev/null || true'
}

configure_fingerprint_resume_recovery() {
  if ! confirm "Install fingerprint resume recovery for suspend/sleep unlock?"; then
    log "Fingerprint resume recovery skipped."
    return 0
  fi

  enable_open_fprintd_sleep_units
  write_fingerprint_resume_hook
  run systemctl daemon-reload
}

setup_fingerprint_auth() {
  local fp_lines

  section "Fingerprint authentication"
  log "Fingerprint setup is based on: https://gist.github.com/borcean/f32c47f6cc52cee33dfc2265ce63f777"

  run dnf install -y fprintd fprintd-pam
  log "Fingerprint USB detection:"
  fp_lines="$(fingerprint_usb_lines)"
  log "${fp_lines:-No fingerprint-like USB device detected by lsusb grep.}"

  if lsusb | grep -qi "$T480_FINGERPRINT_USB_ID"; then
    log "Detected Synaptics $T480_FINGERPRINT_USB_ID, a reader common on ThinkPad T480."
    log "Stock fprintd support may be insufficient; open-fprintd/python3-validity is a community workaround."
    if confirm "Enable COPR $PYTHON_VALIDITY_COPR and install open-fprintd/python3-validity?"; then
      run dnf copr enable -y "$PYTHON_VALIDITY_COPR"
      run dnf install -y open-fprintd fprintd-clients fprintd-clients-pam python3-validity
      run_tolerate systemctl disable --now fprintd
      run systemctl enable --now open-fprintd python3-validity
      prepare_validity_fingerprint_reader
    else
      log "COPR/open-fprintd setup skipped."
    fi
  fi

  run authselect enable-feature with-fingerprint
  run authselect apply-changes
  run_tolerate authselect current
  run_tolerate authselect check
  configure_fingerprint_resume_recovery

  if [ -n "$REAL_USER" ] && confirm "Run fprintd-enroll for user $REAL_USER now?"; then
    run_as_real_user fprintd-enroll
  else
    log "Fingerprint enrollment skipped. Run manually later as the target user: fprintd-enroll"
  fi
}

run_fingerprint_module() {
  setup_fingerprint_auth
}
