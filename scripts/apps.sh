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

write_slack_repo() {
  local path="/etc/yum.repos.d/slack.repo"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write Slack RPM repository to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
[slack]
name=Slack
baseurl=https://packagecloud.io/slacktechnologies/slack/fedora/21/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://slack.com/gpg/slack_pubkey_20251016.gpg
sslverify=1
metadata_expire=300
EOF
}

install_slack() {
  section "Slack"
  if ! confirm "Install Slack from the Slack RPM repository?"; then
    log "Slack setup skipped."
    return 0
  fi

  run rpm --import https://slack.com/gpg/slack_pubkey_20251016.gpg
  write_slack_repo
  run dnf makecache -y --disablerepo='*' --enablerepo=slack
  run dnf install -y slack
  run_tolerate rpm -q slack
  run_tolerate command -v slack
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

write_vscode_inotify_sysctl() {
  local path="/etc/sysctl.d/99-vscode-inotify.conf"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write VS Code inotify limit to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
# Increase inotify watches for large VS Code workspaces.
fs.inotify.max_user_watches=524288
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

  write_vscode_inotify_sysctl
  run sysctl --system
  run_tolerate cat /proc/sys/fs/inotify/max_user_watches
}

install_zed() {
  section "Zed"
  if ! confirm "Install Zed editor using the official Zed Linux installer?"; then
    log "Zed setup skipped."
    return 0
  fi

  if [ -z "$REAL_USER" ]; then
    log "No non-root SUDO_USER detected; skipping Zed user install."
    log "Run manually as the target user:"
    log "  curl -f https://zed.dev/install.sh | sh"
    return 0
  fi

  run dnf install -y curl
  run_as_real_user sh -c 'tmp="$(mktemp)" && trap '\''rm -f "$tmp"'\'' EXIT && curl -fsSL https://zed.dev/install.sh -o "$tmp" && sh "$tmp"'
  run_as_real_user sh -c 'test -x "$HOME/.local/bin/zed"'
  run_as_real_user sh -c '"$HOME/.local/bin/zed" --version'
}

run_apps_module() {
  install_1password
  install_bitwarden
  install_slack
  install_github_cli
  install_vscode
  install_zed
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main apps run_apps_module "$@"
fi
