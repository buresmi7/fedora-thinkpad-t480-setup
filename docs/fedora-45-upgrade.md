# Fedora 45 upgrade

The Fedora 44 to 45 upgrade was completed and checked on a ThinkPad T480 on
2026-11-10. The upgraded system runs Python 3.15.2, GDM 51.1.1,
`open-fprintd-0.7-1.fc45`, and `python3-validity-0.15-1.fc45.local1` with the
Synaptics `06cb:009a` fingerprint reader. Existing fingerprint enrollment was
preserved, and screen unlocking with the enrolled finger was verified after
reboot.

## Fingerprint login behavior

GNOME 51 requires a password to start a new login session, including after a
reboot or a full logout. Fingerprints remain available to unlock an existing
session. Locking with Super+L does not log the user out, even though the unlock
screen resembles the login screen. This is an intentional GNOME change for
security and keyring compatibility; see the [GDM 51 release notes](https://github.com/GNOME/gdm/blob/51.1.1/NEWS).

A successful sensor test does not verify the login policy. Check both driver
availability and actual screen unlocking after an upgrade:

```bash
rpm -q python3-validity open-fprintd fprintd-clients fprintd-clients-pam gdm
systemctl is-active python3-validity open-fprintd
authselect check
fprintd-list "$(id -un)"
```

Then lock with Super+L and test the enrolled finger. Do not reset the sensor or
re-enroll fingerprints to change the new-login behavior. The existing suspend
recovery hook remains in use.

## Python 3.15 compatibility

At the time of the upgrade, the `sneexy/python-validity` Fedora 45 Copr repository
still offered a Fedora 44 build requiring Python 3.14. That package cannot satisfy
the Fedora 45 Python ABI dependency. Do not force installation with `--nodeps`,
remove fingerprint packages to satisfy the solver, or disable repository signature
checks globally.

The working package was rebuilt from this signed source RPM, whose signature was
verified with the already trusted Copr RPM key:

- [Original source RPM](https://copr-be.cloud.fedoraproject.org/results/sneexy/python-validity/fedora-45-x86_64/09643221-python-validity/python-validity-0.15-1.fc44.src.rpm)
- Source SHA-256: `045db230cc4da3f23e821489dc16944c880377753d7783f38d3c87e4cb64ddd7`
- Fedora 45 build image: `registry.fedoraproject.org/fedora@sha256:3632de47c2cef45d6a6ea6a420280ff9ce452e225a1b291299c105b9d9bae471`

Only the RPM release and changelog changed; the driver Python source was
unchanged. The patch is [assets/python-validity-fedora45.patch](../assets/python-validity-fedora45.patch).
Build it inside Fedora 45, not with Fedora 44's Python. From the repository root:

```bash
mkdir -p build/python-validity-fedora45
curl --fail --location \
  --output build/python-validity-fedora45/python-validity-0.15-1.fc44.src.rpm \
  https://copr-be.cloud.fedoraproject.org/results/sneexy/python-validity/fedora-45-x86_64/09643221-python-validity/python-validity-0.15-1.fc44.src.rpm
printf '%s  %s\n' \
  045db230cc4da3f23e821489dc16944c880377753d7783f38d3c87e4cb64ddd7 \
  build/python-validity-fedora45/python-validity-0.15-1.fc44.src.rpm \
  | sha256sum --check -
rpmkeys --checksig build/python-validity-fedora45/python-validity-0.15-1.fc44.src.rpm
cp assets/python-validity-fedora45.patch build/python-validity-fedora45/

podman run --rm --userns=keep-id:uid=0,gid=0 \
  --volume "$PWD/build/python-validity-fedora45:/build:Z" \
  registry.fedoraproject.org/fedora@sha256:3632de47c2cef45d6a6ea6a420280ff9ce452e225a1b291299c105b9d9bae471 \
  bash -euxo pipefail -c '
    dnf install -y rpm-build dnf5-plugins patch
    dnf builddep -y /build/python-validity-0.15-1.fc44.src.rpm
    rpm --define "_topdir /build/rpmbuild" -i /build/python-validity-0.15-1.fc44.src.rpm
    cd /build/rpmbuild/SPECS
    patch --batch --forward -p0 < /build/python-validity-fedora45.patch
    rpmbuild --define "_topdir /build/rpmbuild" -ba python-validity.spec
    dnf install -y /build/rpmbuild/RPMS/noarch/python3-validity-0.15-1.fc45.local1.noarch.rpm
    dnf check
    python3 -c "import validitysensor, dbus, usb, yaml, cryptography"
  '
```

Run Podman as the desktop user. The container installs build dependencies in its
own filesystem. Stop if the source checksum or signature check fails; a missing
Copr signing key needs to be resolved before continuing.

The originally tested binary RPM had SHA-256
`9453ccb7e4f7b1c8e369580f93e062c26b3a76b5a10bb1de2af9a898aad53b08`.
This identifies that particular build, not a reproducible hash for future builds.
Validation included dependency checks, importing all 23 driver modules under
Python 3.15, and recognizing the existing enrolled finger on the real sensor
using the Fedora 45 environment. The new host's screen unlock was then verified.

RPM binaries, sensor state, biometric templates, and local configuration backups
are not stored in this repository. Build outputs are ignored by Git.

## Upgrade transaction

Update Fedora 44 first and review a rollback option, such as a pre-upgrade
Snapper root snapshot. A root snapshot does not replace a backup of home data.
Do not run the fingerprint module's firmware preparation during an OS upgrade.

If the Copr repository still lacks a compatible driver, make the rebuilt RPM
available through a temporary local repository. Install `createrepo_c` on the
host, then run from the repository root:

```bash
mkdir -p build/python-validity-fedora45/repo
cp build/python-validity-fedora45/rpmbuild/RPMS/noarch/python3-validity-0.15-1.fc45.local1.noarch.rpm \
  build/python-validity-fedora45/repo/
createrepo_c build/python-validity-fedora45/repo

sudo dnf --releasever=45 \
  --repofrompath="f45-validity-local,file://$PWD/build/python-validity-fedora45/repo" \
  --setopt=f45-validity-local.gpgcheck=0 \
  system-upgrade download
```

The signature exception applies only to the locally built unsigned package.
Signature checks remain enabled for packages from Fedora, Copr, and other remote
repositories. Keep the local repository until the offline upgrade has completed.
Review the transaction: `python3-validity`, `open-fprintd`, `fprintd-clients`, and
`fprintd-clients-pam` must be retained or upgraded. After the download and RPM
transaction test pass, apply the prepared upgrade with `sudo dnf offline reboot`.

The completed upgrade did not require `--allowerasing`. The setup scripts also
use Slack's `slack_pubkey_20260921.gpg` signing key, which was required for the
Slack package update. Existing DNF `gpgkey` overrides can take precedence over
the repository file; inspect `/etc/dnf/repos.override.d/` if the wrong key is
still selected.
