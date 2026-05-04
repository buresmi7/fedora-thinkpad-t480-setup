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
  run_as_real_user docker version
  run_as_real_user docker compose version
  run_as_real_user docker context ls
  run_tolerate command -v code
  run_as_real_user sh -c 'test -x "$HOME/.local/bin/zed" && "$HOME/.local/bin/zed" --version'
  run_as_real_user bash -lc 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; node --version; npm --version'
  run_tolerate bash -c 'cat /sys/class/power_supply/BAT*/charge_control_*_threshold'
}

print_manual_followup() {
  local docker_uid="1000"
  local docker_user="${REAL_USER:-${USER:-}}"

  if [ -n "$docker_user" ]; then
    docker_uid="$(id -u "$docker_user" 2>/dev/null || printf 1000)"
  fi

  section "Manual follow-up"
  log "Reboot may be required after firmware updates, authselect/PAM changes, power management changes, or fingerprint service changes."
  log "Firmware updates may also require AC power and another fwupdmgr update run after reboot."
  log "If fingerprint enrollment was skipped or failed, run as the target user: fprintd-enroll"
  log "Fingerprint resume hook logs: journalctl -b -t t480-fingerprint-resume"
  log "Fingerprint service logs: journalctl -b -u open-fprintd -u python3-validity"
  log "Rootless Docker user service logs as the target user: journalctl --user -u docker.service"
  log "Rootless Docker socket for IDEs/tools: unix:///run/user/${docker_uid}/docker.sock"
  log "Risky throttling fixes were not installed automatically. Review such changes manually before applying them."
}

run_health_module() {
  print_health_report
  print_manual_followup
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main health run_health_module "$@"
fi
