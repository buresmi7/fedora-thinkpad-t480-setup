#!/usr/bin/env bash
# Fedora post-install setup for Lenovo ThinkPad T480.
#
# The setup is split into standalone scripts under ./scripts:
#   baseline.sh    Base packages, firmware, Thunderbolt, RPM Fusion, browser codecs
#   power.sh       Fedora power profiles and ThinkPad battery thresholds
#   fingerprint.sh Fingerprint authentication, python-validity, suspend/resume fix
#   desktop.sh     GNOME/touchpad/temperature/DDC settings
#   docker.sh      Docker Engine, Docker Compose plugin, rootless user daemon
#   apps.sh        1Password, Bitwarden, Slack, GitHub CLI, Visual Studio Code, Zed
#   health.sh      Read-only health report and follow-up notes
#
# Fingerprint setup is based on:
#   https://gist.github.com/borcean/f32c47f6cc52cee33dfc2265ce63f777
#
# Usage:
#   sudo ./setup.sh
#   sudo ./setup.sh --only fingerprint
#   sudo ./setup.sh --only baseline,power,fingerprint
#   sudo ./setup.sh --yes --only fingerprint
#   sudo ./setup.sh --dry-run --all
#
# Each module can also run directly:
#   sudo ./scripts/fingerprint.sh --yes
#   sudo ./scripts/docker.sh --yes

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
PROJECT_DIR="$SCRIPT_DIR"

ASSUME_YES=0
DRY_RUN=0
ONLY_MODULES=""
RUN_ALL=0
REAL_USER="${SUDO_USER:-}"
REAL_HOME=""
FEDORA_VERSION=""

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/baseline.sh
source "$SCRIPT_DIR/scripts/baseline.sh"
# shellcheck source=scripts/power.sh
source "$SCRIPT_DIR/scripts/power.sh"
# shellcheck source=scripts/fingerprint.sh
source "$SCRIPT_DIR/scripts/fingerprint.sh"
# shellcheck source=scripts/desktop.sh
source "$SCRIPT_DIR/scripts/desktop.sh"
# shellcheck source=scripts/docker.sh
source "$SCRIPT_DIR/scripts/docker.sh"
# shellcheck source=scripts/apps.sh
source "$SCRIPT_DIR/scripts/apps.sh"
# shellcheck source=scripts/health.sh
source "$SCRIPT_DIR/scripts/health.sh"

readonly MODULE_IDS=(baseline power fingerprint desktop docker apps health)
readonly MODULE_LABELS=(
  "baseline packages, firmware, Thunderbolt, RPM Fusion, browser codecs"
  "power management and battery thresholds"
  "fingerprint authentication and suspend/resume recovery"
  "GNOME desktop, touchpad, temperature indicator, DDC brightness"
  "Docker Engine, Docker Compose plugin, and rootless user daemon"
  "desktop apps: 1Password, Bitwarden, Slack, GitHub CLI, VS Code, Zed"
  "health report and manual follow-up"
)

usage() {
  cat <<EOF
Usage: sudo ./$SCRIPT_NAME [options]

Fedora post-install setup for Lenovo ThinkPad T480.

Options:
  -y, --yes             Auto-confirm prompts.
  -n, --dry-run         Print commands without executing them.
      --all             Run all modules.
      --only LIST       Run selected modules, comma-separated.
                         Available: baseline,power,fingerprint,desktop,docker,apps,health
  -h, --help            Show this help.

T480 fingerprint BIOS prerequisite:
  Security -> Fingerprint -> Predesktop Authentication -> Disabled
  Then do a full shutdown, wait a few seconds, and boot again.

Standalone modules:
  sudo ./scripts/fingerprint.sh
  sudo ./scripts/docker.sh
  sudo ./scripts/power.sh --dry-run
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes)
        ASSUME_YES=1
        ;;
      -n|--dry-run)
        DRY_RUN=1
        ;;
      --all)
        RUN_ALL=1
        ;;
      --only)
        shift
        if [ "$#" -eq 0 ]; then
          log "--only requires a comma-separated module list." >&2
          exit 2
        fi
        ONLY_MODULES="$1"
        ;;
      --only=*)
        ONLY_MODULES="${1#--only=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log "Unknown option: $1" >&2
        usage
        exit 2
        ;;
    esac
    shift
  done
}

is_known_module() {
  local candidate="$1"
  local module

  for module in "${MODULE_IDS[@]}"; do
    if [ "$candidate" = "$module" ]; then
      return 0
    fi
  done

  return 1
}

module_selected_by_only() {
  local wanted="$1"
  local item
  local normalized="${ONLY_MODULES//,/ }"

  for item in $normalized; do
    if ! is_known_module "$item"; then
      log "Unknown module in --only: $item" >&2
      log "Available modules: ${MODULE_IDS[*]}" >&2
      exit 2
    fi

    if [ "$item" = "$wanted" ]; then
      return 0
    fi
  done

  return 1
}

run_module_by_id() {
  case "$1" in
    baseline) run_baseline_module ;;
    power) run_power_module ;;
    fingerprint) run_fingerprint_module ;;
    desktop) run_desktop_module ;;
    docker) run_docker_module ;;
    apps) run_apps_module ;;
    health) run_health_module ;;
    *)
      log "Unknown module: $1" >&2
      exit 2
      ;;
  esac
}

should_run_module() {
  local module="$1"
  local label="$2"

  if [ "$RUN_ALL" -eq 1 ]; then
    return 0
  fi

  if [ -n "$ONLY_MODULES" ]; then
    module_selected_by_only "$module"
    return $?
  fi

  confirm "Run module '$module' ($label)?"
}

run_selected_modules() {
  local idx
  local module
  local label

  for idx in "${!MODULE_IDS[@]}"; do
    module="${MODULE_IDS[$idx]}"
    label="${MODULE_LABELS[$idx]}"

    if should_run_module "$module" "$label"; then
      run_module_by_id "$module"
    else
      log "Skipping module '$module'."
    fi
  done
}

main() {
  parse_args "$@"
  require_root
  require_fedora
  detect_real_user
  print_header
  run_selected_modules
}

main "$@"
