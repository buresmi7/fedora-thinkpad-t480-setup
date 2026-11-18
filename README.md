# Fedora ThinkPad T480 Setup

Modular Fedora post-install setup for Lenovo ThinkPad T480.

The Fedora 44 to 45 upgrade was verified with the Synaptics `06cb:009a` reader, Python 3.15, and a locally rebuilt `python3-validity` package. See [Fedora 45 upgrade notes](docs/fedora-45-upgrade.md) for the build, upgrade procedure, and fingerprint login behavior in GNOME 51.

If the fingerprint reader works in 1Password but GNOME 51 screen unlocking fails, see the verified [permanent per-user GNOME unlock workaround](docs/fedora-45-upgrade.md#permanent-per-user-gnome-unlock-workaround). It prevents the observed double start without changing PAM, enrollment, or password-only initial login.

## Features

- Baseline Fedora tools and ThinkPad diagnostics.
- Firmware updates through `fwupd`.
- Thunderbolt / USB-C dock support through `bolt`.
- RPM Fusion multimedia and browser video acceleration setup.
- Fedora-native power management through `tuned` / `tuned-ppd`.
- ThinkPad battery charge thresholds without TLP.
- Synaptics fingerprint setup for the T480, including `open-fprintd`, `python-validity`, PAM/authselect, enrollment, and suspend/resume recovery.
- GNOME touchpad defaults, CPU temperature indicator, and DDC/CI external monitor brightness tooling.
- Network preference service that disables Wi-Fi while wired Ethernet is connected, then re-enables Wi-Fi when the cable is unplugged.
- Official Docker Engine with Buildx, Docker Compose plugin, and a rootless per-user Docker daemon.
- Desktop apps: 1Password, Bitwarden, Google Chrome, and Slack.
- Developer tools: GitHub CLI, AWS CLI v2, Visual Studio Code, Zed, nvm, and the latest Node.js LTS installed through nvm.

1Password and Bitwarden are installed as RPM packages instead of Flatpaks. The RPM builds integrate better with the host system, especially for desktop/browser-extension communication and related browser plugin workflows.

Slack is installed from Slack's RPM repository so updates are handled by DNF. The package signature is checked with Slack's current RPM signing key.

Google Chrome is installed from Google's official RPM repository so updates are handled by DNF. The package signature is checked with Google's Linux signing key.

Docker is installed from Docker's official Fedora RPM repository. The setup uses rootless mode for the target `sudo` user, leaves the system-wide rootful Docker service disabled, enables user lingering, and starts `docker.service` through the user's systemd instance. Compose is installed as the modern Docker CLI plugin and is used as `docker compose`.

Visual Studio Code setup raises `fs.inotify.max_user_watches` to `524288` via `/etc/sysctl.d/99-vscode-inotify.conf` for large workspaces.

Zed is installed for the target desktop user with the official Linux installer from `zed.dev`, which places it under `~/.local`. nvm is installed for the target desktop user and then used to install the latest Node.js LTS release; new shells use that LTS release as the default.

AWS CLI v2 is installed or updated from the official AWS Linux ZIP installer.

## Notes

- Slack is forced through XWayland with a per-user `slack.desktop` override using `Exec=/usr/bin/slack --ozone-platform=x11 %U`. Native Wayland Slack receives GNOME notification clicks, but it does not reliably raise the already-running window, so notification click-through depends on this launcher tweak.
- Use Google Chrome for Google Meet. Firefox does not provide hardware encoding for the outgoing Meet stream on this setup, which makes Chrome the better choice for calls.

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
sudo ./setup.sh --only network
sudo ./setup.sh --only dev
sudo ./setup.sh --all
sudo ./setup.sh --dry-run --only desktop
```

Run a module directly:

```bash
sudo ./scripts/fingerprint.sh
sudo ./scripts/docker.sh
sudo ./scripts/dev.sh
sudo ./scripts/power.sh --dry-run
sudo ./scripts/network.sh
sudo ./scripts/health.sh
```

Install the optional GNOME 51 unlock workaround as the desktop user, **without sudo**:

```bash
bash assets/gnome-fingerprint-guards-install enable
```

This is separate from the root-run modules. See the [guide](docs/fedora-45-upgrade.md#permanent-per-user-gnome-unlock-workaround) for prerequisites, validation, upgrade fallback, and rollback. It does not restart the active desktop.

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
- `assets/prefer-wired-network*` - user service files installed by `scripts/network.sh`.
- `assets/prefer-wired-arp.conf` - ARP hardening installed by `scripts/network.sh`.
- `assets/python-validity-fedora45.patch` - RPM release adjustment for the verified Fedora 45 fingerprint driver rebuild.
- `assets/python-validity-jon-fedora45.spec` - pinned T480 fork trial with USB recovery and persistent calibration; see the upgrade notes for validation and rollback.
- `assets/python-validity-cancellation-rpm.patch` / `assets/python-validity-serialize-scans.patch` - experimental cancellation fix, not a confirmed GNOME unlock solution; see the upgrade notes.
- `tests/test_python_validity_cancellation.py` - hardware-free regression tests for the fingerprint cancellation fix.
- `assets/gnome-fingerprint-guards-install` / `assets/gnome-fingerprint-guards-persistent.conf` - permanent per-user GNOME 51 unlock workaround, with backup and rollback; not enabled by the root-run setup modules.
- `assets/gnome-fingerprint-guards.py` - source-checksummed overlay generator that falls back to the packaged GNOME code after an unreviewed update.
- `assets/gnome-fingerprint-guards-trial` / `assets/gnome-fingerprint-guards.conf` - original runtime-only trial, retained for reproducing the investigation.
- `tests/test_gnome_fingerprint_guards.py` - hardware-free tests for that GNOME trial; actual screen unlocking must be checked separately.
- `tests/test_gnome_fingerprint_install.py` - isolated tests of permanent installation, migration, refusal to overwrite unrelated files, and rollback.
- `docs/fedora-45-upgrade.md` - Fedora 45 migration and fingerprint compatibility notes.

The fingerprint suspend/resume hook is not meant to be run manually. It is copied to `/usr/lib/systemd/system-sleep/t480-fingerprint-resume`.

## Network Note

On systems where Ethernet and Wi-Fi are connected to the same LAN, NetworkManager can report address conflicts and long-lived SSH/Git sessions can stall or time out. The `network` module installs host-wide ARP settings that keep each interface's ARP identity scoped to that interface while preserving normal duplicate-address detection. It also installs a user systemd service that prefers the detected wired Ethernet device and turns Wi-Fi back on only when the cable is disconnected. When Wi-Fi is restored, NetworkManager selects the best available saved profile by its normal autoconnect priority instead of forcing a specific SSID.
