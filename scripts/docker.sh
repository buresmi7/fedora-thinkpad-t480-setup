#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

readonly DOCKER_PACKAGES=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
  docker-ce-rootless-extras
  fuse-overlayfs
  slirp4netns
  shadow-utils
)

remove_conflicting_docker_packages() {
  section "Docker package conflicts"
  run_tolerate dnf remove -y \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-selinux \
    docker-engine-selinux \
    docker-engine
}

setup_docker_repository() {
  section "Docker RPM repository"

  run rpm --import https://download.docker.com/linux/fedora/gpg

  if dnf --version 2>/dev/null | grep -qi '^dnf5'; then
    run dnf install -y dnf5-plugins
    run dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  else
    run dnf install -y 'dnf-command(config-manager)'
    run dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  fi

  run dnf makecache -y --disablerepo='*' --enablerepo=docker-ce-stable
}

install_docker_packages() {
  section "Docker Engine, Buildx, Compose, and rootless extras"
  run dnf install -y "${DOCKER_PACKAGES[@]}"
  run_tolerate rpm -q docker-ce docker-ce-cli docker-compose-plugin docker-ce-rootless-extras
  run_tolerate docker --version
  run_tolerate docker compose version
  run_tolerate command -v dockerd-rootless-setuptool.sh
}

subid_file_has_user_range() {
  local path="$1"
  local user="$2"

  [ -r "$path" ] || return 1
  awk -F: -v user="$user" '$1 == user && $3 >= 65536 { found = 1 } END { exit found ? 0 : 1 }' "$path"
}

find_free_subid_start() {
  local path="$1"

  if [ ! -r "$path" ]; then
    printf '%s\n' 100000
    return 0
  fi

  awk -F: '
    BEGIN {
      size = 65536
      first = 100000
      max = 2147483647
    }
    $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
      start[++count] = $2
      end[count] = $2 + $3 - 1
    }
    END {
      for (candidate = first; candidate + size - 1 < max; candidate += size) {
        ok = 1
        candidate_end = candidate + size - 1
        for (idx = 1; idx <= count; idx++) {
          if (candidate <= end[idx] && start[idx] <= candidate_end) {
            ok = 0
            break
          }
        }
        if (ok) {
          print candidate
          exit 0
        }
      }
      exit 1
    }
  ' "$path"
}

ensure_subid_file() {
  local path="$1"

  if [ -e "$path" ]; then
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would create $path"
    return 0
  fi

  run touch "$path"
}

ensure_user_subids() {
  local path="$1"
  local flag="$2"
  local label="$3"
  local start
  local end

  ensure_subid_file "$path"

  if subid_file_has_user_range "$path" "$REAL_USER"; then
    log "$REAL_USER already has a sufficient $label range in $path."
    return 0
  fi

  start="$(find_free_subid_start "$path")"
  end="$((start + 65535))"
  run usermod "$flag" "$start-$end" "$REAL_USER"
}

ensure_rootless_prerequisites() {
  section "Rootless Docker prerequisites"

  if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    log "No non-root SUDO_USER detected; rootless Docker user setup skipped."
    log "Run this setup with sudo from the target desktop user account."
    return 1
  fi

  ensure_user_subids /etc/subuid --add-subuids "subuid"
  ensure_user_subids /etc/subgid --add-subgids "subgid"
}

start_real_user_systemd() {
  local real_uid

  real_uid="$(id -u "$REAL_USER")"
  run loginctl enable-linger "$REAL_USER"
  run systemctl start "user@${real_uid}.service"
}

install_rootless_docker_service() {
  local user_service="$REAL_HOME/.config/systemd/user/docker.service"

  section "Rootless Docker daemon"

  run_tolerate systemctl disable --now docker.service docker.socket
  start_real_user_systemd

  if [ -f "$user_service" ]; then
    log "Rootless Docker user service already exists: $user_service"
  else
    run_as_real_user dockerd-rootless-setuptool.sh install
  fi

  run_as_real_user systemctl --user daemon-reload
  run_as_real_user systemctl --user enable --now docker.service
  run_as_real_user docker context use rootless
}

verify_rootless_docker() {
  section "Rootless Docker verification"
  run_as_real_user docker version
  run_as_real_user docker compose version
  run_as_real_user docker info

  log "Rootless Docker socket for tools that need DOCKER_HOST:"
  log "  unix:///run/user/$(id -u "$REAL_USER")/docker.sock"

  if confirm "Run Docker hello-world under the rootless user daemon?"; then
    run_as_real_user docker run --rm hello-world
  else
    log "Docker hello-world skipped. Test later as $REAL_USER: docker run --rm hello-world"
  fi
}

run_docker_module() {
  if ! confirm "Install official Docker Engine with Compose plugin in rootless mode for ${REAL_USER:-target user}?"; then
    log "Docker rootless setup skipped."
    return 0
  fi

  remove_conflicting_docker_packages
  setup_docker_repository
  install_docker_packages

  if ensure_rootless_prerequisites; then
    install_rootless_docker_service
    verify_rootless_docker
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main docker run_docker_module "$@"
fi
