# Fedora ThinkPad T480 Setup

Modular Fedora post-install setup for Lenovo ThinkPad T480.

## Features

- Baseline Fedora tools and ThinkPad diagnostics.
- Firmware updates through `fwupd`.
- Thunderbolt / USB-C dock support through `bolt`.
- RPM Fusion multimedia and browser video acceleration setup.
- Fedora-native power management through `tuned` / `tuned-ppd`.
- ThinkPad battery charge thresholds without TLP.
- Synaptics fingerprint setup for the T480, including `open-fprintd`, `python-validity`, PAM/authselect, enrollment, and suspend/resume recovery.
- GNOME touchpad defaults, CPU temperature indicator, and DDC/CI external monitor brightness tooling.
- Official Docker Engine with Buildx, Docker Compose plugin, and a rootless per-user Docker daemon.
- Desktop apps: 1Password, Bitwarden, Slack, GitHub CLI, Visual Studio Code, and Zed.

1Password and Bitwarden are installed as RPM packages instead of Flatpaks. The RPM builds integrate better with the host system, especially for desktop/browser-extension communication and related browser plugin workflows.

Slack is installed from Slack's RPM repository so updates are handled by DNF. The package signature is checked with Slack's current RPM signing key.

Visual Studio Code setup raises `fs.inotify.max_user_watches` to `524288` via `/etc/sysctl.d/99-vscode-inotify.conf` for large workspaces.

Zed is installed for the target desktop user with the official Linux installer from `zed.dev`, which places it under `~/.local`.

Docker is installed from Docker's official Fedora RPM repository. The setup uses rootless mode for the target `sudo` user, leaves the system-wide rootful Docker service disabled, enables user lingering, and starts `docker.service` through the user's systemd instance. Compose is installed as the modern Docker CLI plugin and is used as `docker compose`.

## Usage

Run the interactive wrapper:

```bash
sudo ./setup.sh
```

Run selected modules through the wrapper:

```bash
sudo ./setup.sh --only fingerprint
sudo ./setup.sh --only baseline,power,fingerprint
sudo ./setup.sh --only docker
sudo ./setup.sh --all
sudo ./setup.sh --dry-run --only desktop
```

Run a module directly:

```bash
sudo ./scripts/fingerprint.sh
sudo ./scripts/docker.sh
sudo ./scripts/power.sh --dry-run
sudo ./scripts/health.sh
```

Re-run only the GNOME desktop setup, including the CPU temperature indicator:

```bash
sudo ./scripts/desktop.sh
```

If the Freon temperature indicator does not appear immediately, log out and back in, then check it in the GNOME Extensions app.

## Layout

- `setup.sh` - interactive/selective wrapper.
- `scripts/*.sh` - standalone setup scripts, each with one responsibility.
- `lib/common.sh` - shared shell helpers.
- `assets/t480-fingerprint-resume` - systemd sleep hook template installed by `scripts/fingerprint.sh`.

The fingerprint suspend/resume hook is not meant to be run manually. It is copied to `/usr/lib/systemd/system-sleep/t480-fingerprint-resume`.
