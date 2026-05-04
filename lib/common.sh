#!/usr/bin/env bash

: "${ASSUME_YES:=0}"
: "${DRY_RUN:=0}"
: "${REAL_USER:=${SUDO_USER:-}}"
: "${REAL_HOME:=}"
: "${FEDORA_VERSION:=}"

log() {
  printf '%b\n' "$*"
}

section() {
  log "\n================================================================"
  log "== $*"
  log "================================================================"
}

confirm() {
  local prompt="$1"
  local answer

  if [ "$ASSUME_YES" -eq 1 ]; then
    log "$prompt [auto-yes]"
    return 0
  fi

  read -r -p "$prompt [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

quote_cmd() {
  printf '%q ' "$@"
}

run() {
  log "\n$ $(quote_cmd "$@")"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  "$@"
}

run_tolerate() {
  if ! run "$@"; then
    log "Command failed but is non-critical; continuing."
  fi
}

run_as_real_user() {
  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    log "No non-root SUDO_USER detected; skipping user command: $(quote_cmd "$@")"
    return 0
  fi

  run_tolerate sudo -H -u "$REAL_USER" env \
    HOME="$REAL_HOME" \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus" \
    "$@"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "Run this script with sudo:"
    log "  sudo ./$(basename "$0")"
    exit 1
  fi
}

require_fedora() {
  if [ ! -r /etc/os-release ] || ! grep -qi '^ID=fedora$' /etc/os-release; then
    log "This script is intended for Fedora only."
    exit 1
  fi

  FEDORA_VERSION="$(rpm -E %fedora)"
  if ! [[ "$FEDORA_VERSION" =~ ^[0-9]+$ ]]; then
    log "Could not detect Fedora version with: rpm -E %fedora"
    exit 1
  fi
}

detect_real_user() {
  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER="$(logname 2>/dev/null || true)"
  fi

  if [ -n "$REAL_USER" ] && getent passwd "$REAL_USER" >/dev/null; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
  else
    REAL_USER=""
    REAL_HOME=""
  fi
}

print_header() {
  section "Fedora ThinkPad T480 setup"
  log "Date: $(date)"
  log "Fedora version: $FEDORA_VERSION"
  log "Real user: ${REAL_USER:-not detected}"
  log "Dry run: $DRY_RUN"
  log "Assume yes: $ASSUME_YES"
}
