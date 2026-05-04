#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_DIR:=$(cd "$MODULE_DIR/.." && pwd)}"

if [ -z "${T480_COMMON_LOADED:-}" ]; then
  # shellcheck source=../lib/common.sh
  source "$PROJECT_DIR/lib/common.sh"
fi

readonly BASELINE_PACKAGES=(
  curl
  wget
  git
  unzip
  tar
  vim
  nano
  htop
  btop
  fastfetch
  lm_sensors
  pciutils
  usbutils
  util-linux-user
  upower
  fwupd
  bolt
  libva-utils
  libva-intel-media-driver
  ddcutil
  i2c-tools
)

install_baseline_packages() {
  section "Baseline packages"
  run dnf install -y "${BASELINE_PACKAGES[@]}"
}

setup_firmware_fwupd() {
  section "Firmware via fwupd"
  run systemctl enable --now fwupd-refresh.timer
  run_tolerate fwupdmgr refresh --force
  run_tolerate fwupdmgr get-updates

  if confirm "Run fwupdmgr update now? Firmware updates may require reboot and AC power."; then
    run fwupdmgr update
  else
    log "Firmware update skipped. Run manually later: sudo fwupdmgr update"
  fi
}

setup_thunderbolt_bolt() {
  section "Thunderbolt / USB-C dock support"
  run systemctl enable --now bolt
  run_tolerate boltctl
}

setup_rpmfusion_multimedia() {
  section "RPM Fusion and multimedia codecs"
  if ! confirm "Enable RPM Fusion free/nonfree repositories and install multimedia codecs?"; then
    log "RPM Fusion and multimedia setup skipped."
    return 0
  fi

  run dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
  run_tolerate dnf group install -y multimedia
  run_tolerate dnf swap -y ffmpeg-free ffmpeg --allowerasing
  run_tolerate dnf install -y gstreamer1-plugin-openh264 mozilla-openh264 libva-utils libva-intel-media-driver libavcodec-freeworld
}

install_browser_acceleration() {
  section "Browser hardware acceleration"
  run dnf install -y libva-utils libva-intel-media-driver

  if confirm "Install RPM Fusion ffmpeg codecs for better Firefox/Meet video support?"; then
    run_tolerate dnf swap -y ffmpeg-free ffmpeg --allowerasing
    run_tolerate dnf install -y libavcodec-freeworld
  else
    log "RPM Fusion ffmpeg codecs for browser acceleration skipped."
  fi

  run_tolerate vainfo

  log "Check Firefox at about:support:"
  log "  Compositing should be WebRender"
  log "  HARDWARE_VIDEO_DECODING should be available by default"
}

run_baseline_module() {
  install_baseline_packages
  setup_firmware_fwupd
  setup_thunderbolt_bolt
  setup_rpmfusion_multimedia
  install_browser_acceleration
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  standalone_main baseline run_baseline_module "$@"
fi
