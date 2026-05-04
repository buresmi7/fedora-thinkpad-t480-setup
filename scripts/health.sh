#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

print_health_report() {
  section "Health report"
  run_tolerate hostnamectl
  run_tolerate fwupdmgr get-devices
  run_tolerate bash -c 'upower -e | grep -i battery | while read -r bat; do echo "--- ${bat}"; upower -i "${bat}"; done'
  run_tolerate bash -c "lsusb | grep -Ei 'finger|synaptics|06cb:009a'"
  run_tolerate sensors
  run_tolerate vainfo
  run_tolerate tuned-adm active
  run_tolerate tuned-adm recommend
  run_tolerate bash -c 'cat /sys/class/power_supply/BAT*/charge_control_*_threshold'
}

print_manual_followup() {
  section "Manual follow-up"
  log "Reboot may be required after firmware updates, authselect/PAM changes, power management changes, or fingerprint service changes."
  log "Firmware updates may also require AC power and another fwupdmgr update run after reboot."
  log "If fingerprint enrollment was skipped or failed, run as the target user: fprintd-enroll"
  log "Fingerprint resume hook logs: journalctl -b -t t480-fingerprint-resume"
  log "Fingerprint service logs: journalctl -b -u open-fprintd -u python3-validity"
  log "Risky throttling fixes were not installed automatically. Review such changes manually before applying them."
}

run_health_module() {
  print_health_report
  print_manual_followup
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main health run_health_module "$@"
fi
