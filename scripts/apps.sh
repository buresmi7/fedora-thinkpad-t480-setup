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

write_google_chrome_repo() {
  local path="/etc/yum.repos.d/google-chrome.repo"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run: would write Google Chrome RPM repository to $path"
    return 0
  fi

  cat > "$path" <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
}

install_google_chrome() {
  section "Google Chrome"
  if ! confirm "Install Google Chrome from the official Google RPM repository?"; then
    log "Google Chrome setup skipped."
    return 0
  fi

  run rpm --import https://dl.google.com/linux/linux_signing_key.pub
  write_google_chrome_repo
  run dnf makecache -y --disablerepo='*' --enablerepo=google-chrome
  run dnf install -y google-chrome-stable
  run_tolerate rpm -q google-chrome-stable
  run_tolerate command -v google-chrome-stable
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

run_apps_module() {
  install_1password
  install_bitwarden
  install_google_chrome
  install_slack
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main apps run_apps_module "$@"
fi
