#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

readonly NVM_VERSION="v0.40.4"
readonly NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
readonly AWS_CLI_V2_INSTALL_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"

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

install_aws_cli_v2() {
  section "AWS CLI v2"
  if ! confirm "Install or update AWS CLI v2 from the official AWS installer?"; then
    log "AWS CLI v2 setup skipped."
    return 0
  fi

  run dnf install -y curl unzip
  run env AWS_CLI_V2_INSTALL_URL="$AWS_CLI_V2_INSTALL_URL" bash -c 'tmpdir="$(mktemp -d)" && trap '\''rm -rf "$tmpdir"'\'' EXIT && curl -fsSL "$AWS_CLI_V2_INSTALL_URL" -o "$tmpdir/awscliv2.zip" && unzip -q "$tmpdir/awscliv2.zip" -d "$tmpdir" && "$tmpdir/aws/install" --update'
  run_tolerate command -v aws
  run_tolerate aws --version
}

install_nvm_node_lts() {
  section "nvm and Node.js LTS"
  if ! confirm "Install nvm ${NVM_VERSION} and latest Node.js LTS for ${REAL_USER:-target user}?"; then
    log "nvm and Node.js LTS setup skipped."
    return 0
  fi

  if [ -z "$REAL_USER" ]; then
    log "No non-root SUDO_USER detected; skipping nvm user install."
    log "Run this setup with sudo from the target desktop user account."
    return 0
  fi

  run dnf install -y curl git tar xz
  run_as_real_user env NVM_INSTALL_URL="$NVM_INSTALL_URL" PROFILE="$REAL_HOME/.bashrc" bash -c 'tmp="$(mktemp)" && trap '\''rm -f "$tmp"'\'' EXIT && curl -fsSL "$NVM_INSTALL_URL" -o "$tmp" && bash "$tmp"'
  run_as_real_user bash -lc 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; nvm install --lts; nvm alias default "$(nvm current)"; nvm use default; node --version; npm --version'
}

run_dev_module() {
  install_vscode
  install_zed
  install_github_cli
  install_aws_cli_v2
  install_nvm_node_lts
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main dev run_dev_module "$@"
fi
