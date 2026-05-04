#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

write_1password_repo() {
  local path="/etc/yum.repos.d/1password.repo"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write 1Password RPM repository to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
}

install_1password() {
  section "1Password"
  if ! confirm "Install 1Password from the official 1Password RPM repository?"; then
    log "1Password setup skipped."
    return 0
  fi

  run rpm --import https://downloads.1password.com/linux/keys/1password.asc
  write_1password_repo
  run dnf makecache -y
  run dnf install -y 1password
  run_tolerate rpm -q 1password
  run_tolerate command -v 1password
  run_tolerate command -v op
}

install_bitwarden() {
  local bitwarden_rpm_url="https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm"

  section "Bitwarden"
  if ! confirm "Install Bitwarden desktop from the official RPM package, not Flatpak?"; then
    log "Bitwarden RPM setup skipped."
    return 0
  fi

  run dnf install -y "$bitwarden_rpm_url"
  run_tolerate rpm -q bitwarden
  run_tolerate command -v bitwarden
}

install_github_cli() {
  section "GitHub CLI"
  if ! confirm "Install GitHub CLI (gh) from the official GitHub CLI RPM repository?"; then
    log "GitHub CLI setup skipped."
    return 0
  fi

  if dnf --version 2>/dev/null | grep -qi '^dnf5'; then
    run dnf install -y dnf5-plugins
    run dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
  else
    run dnf install -y 'dnf-command(config-manager)'
    run dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
  fi

  run dnf install -y gh --repo gh-cli
  run_tolerate rpm -q gh
  run_tolerate gh --version
}

write_vscode_repo() {
  local path="/etc/yum.repos.d/vscode.repo"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write Visual Studio Code RPM repository to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
}

install_vscode() {
  section "Visual Studio Code"
  if ! confirm "Install Visual Studio Code from the official Microsoft RPM repository?"; then
    log "Visual Studio Code setup skipped."
    return 0
  fi

  run rpm --import https://packages.microsoft.com/keys/microsoft.asc
  write_vscode_repo
  run_tolerate dnf check-update
  run dnf install -y code
  run_tolerate rpm -q code
  run_tolerate command -v code
}

run_apps_module() {
  install_1password
  install_bitwarden
  install_github_cli
  install_vscode
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main apps run_apps_module "$@"
fi
