# Fedora ThinkPad T480 Setup

Modular Fedora post-install setup for Lenovo ThinkPad T480.

## Usage

Run the interactive wrapper:

```bash
sudo ./setup.sh
```

Run selected modules through the wrapper:

```bash
sudo ./setup.sh --only fingerprint
sudo ./setup.sh --only baseline,power,fingerprint
sudo ./setup.sh --all
sudo ./setup.sh --dry-run --only desktop
```

Run a module directly:

```bash
sudo ./scripts/fingerprint.sh
sudo ./scripts/power.sh --dry-run
sudo ./scripts/health.sh
```

## Layout

- `setup.sh` - interactive/selective wrapper.
- `scripts/*.sh` - standalone setup scripts, each with one responsibility.
- `lib/common.sh` - shared shell helpers.
- `assets/t480-fingerprint-resume` - systemd sleep hook template installed by `scripts/fingerprint.sh`.

The fingerprint suspend/resume hook is not meant to be run manually. It is copied to `/usr/lib/systemd/system-sleep/t480-fingerprint-resume`.
