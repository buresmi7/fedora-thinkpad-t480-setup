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

For the confirmed GNOME 51 double-start problem on this laptop, use the
[permanent per-user unlock workaround](#permanent-per-user-gnome-unlock-workaround)
below. It does not enable fingerprint authentication for a new login session.

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

## Permanent per-user GNOME unlock workaround

This is the retained configuration after the successful trial on 2026-11-17.
The reader worked in 1Password, but GNOME rapidly cancelled and restarted
verification, leaving two driver threads consuming each other's USB events.
Three lifecycle guards from
[Fedora bug 2549082, comment 3](https://bugzilla.redhat.com/show_bug.cgi?id=2549082#c3)
prevent the premature fingerprint start and inappropriate resets. The full
initial-login workaround from that comment is **not** installed. Only the
current desktop user's `org.gnome.Shell@user.service` is configured; GDM, PAM,
1Password, the fingerprint driver, calibration, and enrollment are untouched.

### Install or reproduce

Start with a working enrolled reader and GNOME Shell 51.1 on Fedora 45. This
overlay is not a driver installer; do not factory-reset or re-enroll merely to
apply it. Python 3 with GI, a running systemd user manager, and Node.js for
installation-time syntax checks are required. Node.js is not needed at login.

From the repository root, run as the **desktop user, without sudo**:

```bash
python3 -B tests/test_gnome_fingerprint_guards.py -v
python3 -B tests/test_gnome_fingerprint_install.py -v
bash assets/gnome-fingerprint-guards-install enable
```

The installer refuses unknown/edited target files and unrelated resource
overlays. Re-running the same reviewed installer is safe. Known runtime-only
trial overrides are backed up and removed, while the current trial's generated
JS is retained for the still-running desktop. It does not stop or restart GNOME.
Installation failures restore the prior overrides. No root authentication is
needed, and the root-run setup modules do not enable this user overlay by default.

Persistent files are stored outside the checkout:

- `~/.config/systemd/user/org.gnome.Shell@user.service.d/90-t480-fingerprint-guards.conf`
  is the permanent user-service drop-in.
- `~/.local/libexec/t480-gnome-fingerprint/` contains the generator, reviewed
  drop-in template, and an independent `manage.sh` installer/rollback command.
- `~/.local/state/fedora-t480-setup/gnome-fingerprint-backups/change.*/` contains
  private backups and the preflight output. These are not committed to Git.

The drop-in uses `RuntimeDirectory=t480-gnome-fingerprint` with mode 0700.
Systemd recreates `/run/user/<uid>/t480-gnome-fingerprint/` before each GNOME
start, and the helper generates `authServicesLegacy.js` there. The resource is
regenerated from the installed package after reboot rather than relying on a
file left over from a previous session. The configuration and helper survive
reboot even though this generated output does not. They do not depend on this
Paseo worktree or its lifetime.

If installing from scratch, save work and log out/back in with the password to
load the overlay. When promoting an already active successful trial, the current
desktop keeps the same working code and the persistent paths take over at the
next login/reboot. Never automatically restart GDM/GNOME on Wayland; that ends
the active desktop and may lose unsaved work. A new login still requires the
password; use Super+L to test subsequent fingerprint screen unlocking.

### Verify and handle GNOME updates

```bash
bash "$HOME/.local/libexec/t480-gnome-fingerprint/manage.sh" status
systemctl --user show org.gnome.Shell@user.service \
  -p DropInPaths -p ExecStartPre -p RuntimeDirectory -p RuntimeDirectoryMode
journalctl --user -u org.gnome.Shell@user.service -b --no-pager \
  --grep='T480-GNOME-FPRINT|authServicesLegacy.js'
```

The configured drop-in must be under `~/.config`, not only `/run/user`. After a
new GNOME start, look for `prepared three lifecycle guards` and the actual
resource-overlay load, then verify real Super+L unlocking. `ExecStartPre` showing
no recorded invocation immediately after installation is expected: the desktop
was not restarted. The first new login after reboot remains password-only.

The generator requires the reviewed source SHA-256
`3b0c729d4993f2d41e19f7a5e7b6436b7bf0226fec84f75929679934ee9d9952`
and exactly matching patch contexts. If a GNOME update changes that source, it
removes stale output and logs `overlay skipped`; GLib then uses the packaged
resource. The preparatory command is non-fatal so a helper failure does not block
desktop startup. Fingerprint unlocking may revert to the stock behavior until
the new source is reviewed. Do not remove the checksum guard or silently apply
old replacements to new code. First check whether the upstream fix is already
present; if not, review and test a new generator/installer version. The installer
intentionally refuses to overwrite a different installed version without that
review; retain the existing files in a private backup before replacing them.

On this laptop, 17 real-source guard tests and nine isolated installer tests
passed. They cover initial-selection behavior, password/credential paths,
unknown-source fallback, migration, idempotence, refusing unrelated edits, and
rollback after a reload failure. A separate real systemd user oneshot created a
fresh 0700 runtime directory and generated JS byte-identical to the working
trial, then cleaned up its output. Unit verification passed; the running GNOME
and fingerprint daemons were not restarted. An actual reboot was not performed
as part of deployment. The user confirmed continued reliable unlocking before
requesting this permanent installation.

### Disable or re-enable without the repository

```bash
bash "$HOME/.local/libexec/t480-gnome-fingerprint/manage.sh" disable
# Later, to restore exactly this installed, reviewed version:
bash "$HOME/.local/libexec/t480-gnome-fingerprint/manage.sh" enable
```

Disable only removes this workaround's checksum-verified persistent/runtime
drop-ins, retaining backups and installed helpers. It does not stop the active
desktop; the next full login uses the packaged GNOME resource. If necessary,
run the same disable command from a text console as the desktop user. Do not
use `systemctl --user revert` on the entire unit: it could remove unrelated
overrides. Changing the config alone cannot unload code from an already running
GNOME process.

## Experimental fingerprint cancellation fix (local2)

On 2026-11-16, investigation of a failed GNOME unlock exposed a cancellation race in
`python-validity`: GNOME stopped verification and immediately started another
attempt, but the old scan thread was still running. The USB polling method
cleared the cancellation flag again, allowing two threads to read the same
sensor. A standalone successful `fprintd-verify` did not rule out this race.

The `0.15-1.fc45.local2` rebuild includes
[python-validity-serialize-scans.patch](../assets/python-validity-serialize-scans.patch).
It waits for the previous scan to finish before starting another, preserves
cancellation across USB reads, and suppresses results from cancelled scans.
A stuck scan is given at most three seconds to stop; if it does not, the next
operation is refused instead of starting a second worker. Enrollment, suspend,
and resume use the same serialization. Fingerprint matching, enrolled templates,
and PAM policy are not changed.

The hardware-free regression suite is
[tests/test_python_validity_cancellation.py](../tests/test_python_validity_cancellation.py).
It runs the actual driver methods with a mock transport and covers cancellation,
rapid restarts, late results, an unresponsive worker, enrollment serialization,
and both successful and rejected user matching. The original code fails eight
of ten tests; the patched code passes all ten. These tests do not replace real
screen-unlock and suspend/resume tests, which must also be performed after
installing the package.

The `local2` RPM was installed on this T480 on 2026-11-16. All ten regression
tests also passed against the installed host files, and eight rapid
start/stop/reclaim cycles on the real reader left no worker running after
`VerifyStop` (four threads during a scan, back to the three-thread idle baseline;
stop time 16–19 ms). The existing right-index enrollment remained available.
However, the subsequent manual GNOME unlock test still failed: the driver emitted
`verify-no-match`, then repeated `verify-retry-scan`, and the user unlocked with
a password. A cancellation timeout was also logged. Therefore `local2` fixes the
reproduced thread race but is not a verified solution for the complete unlock
problem. Do not treat the automated pass as proof that GNOME unlocking works.

The experimental package was subsequently downgraded to the retained `local1`
RPM and the driver service restarted; enrollment and PAM were not changed.
A follow-up status check found both daemons active, but `ListEnrolledFingers`
failed with `Unexpected TLS version 4 0`. Thus reverting the experiment did not
resolve the underlying reader communication problem either. An active systemd
service alone must not be reported as a working fingerprint reader.

## Pinned jon-mun T480 fork trial (local3, 2026-11-17)

At the user's request, a separate RPM was built from
[jon-mun's T480 branch](https://github.com/jon-mun/python-validity/tree/t480-fingerprint-0.15-pr290),
pinned at `960b44bda3781b317272211e73856b5a9b0fb0e4`. This is PR #290 plus
persistent host calibration under `/var/lib/python-validity/` with a private
0700 directory. It is not combined with the failed `local2` cancellation patch.

- [Pinned source archive](https://github.com/jon-mun/python-validity/archive/960b44bda3781b317272211e73856b5a9b0fb0e4.tar.gz)
- Source archive SHA-256: `1cdf78a8be2262ad66a5b4c828267e013acaaab0fe75128878a4efa9709d417e`
- [Fedora 45 RPM spec](../assets/python-validity-jon-fedora45.spec)
- Binary RPM SHA-256: `35f9131fd0b679d8bf24d85b32bc23eb0114a23f1a744c30b87127c75282e3ca`
- Source RPM SHA-256: `a6ca41deb254998791dfd4730279344f017ec9a590b3e996ee1a0b0f52d67e53`

The fork's 17 tests passed in the Fedora 45 build and again against the installed
RPM in an isolated Fedora 45 container. All 23 driver modules imported under
Python 3.15. Dependency checks passed and the state directory was mode 0700.
RPM's normal Python shebang rewrite was the only difference in the installed
DBus script; module source files matched the pinned archive.
These checks alone do not confirm real GNOME unlocking or suspend/resume.

The host was switched to `python3-validity-0.15-1.fc45.local3` at 10:20 CET on
2026-11-17. Both services started without an automatic restart, the driver had
its normal three-thread idle baseline, and `fprintd-list michal` successfully
listed the existing right-index finger instead of the preceding TLS error.
The calibration copy still matched the private backup after activation.
The manual Super+L unlock test at 10:21–10:22 CET failed: repeated
`verify-retry-scan` signals were followed by two `verify-no-match` results when
verification was cancelled, and the user unlocked with a password. Both services
remained active with `NRestarts=0` and the driver returned to three idle threads.
Thus this fork alone is not a working fix for the laptop's GNOME unlock problem.
Suspend/resume has not been tested with this build.
An additional standalone `fprintd-verify` test expired after 45 seconds without
a verification result. The user subsequently reported that the reader reacted
but authentication did not succeed; the timing of that touch relative to the
test window was not established. A timeout is not a confirmed rejected
fingerprint. After both tests the same driver PID remained active with
`NRestarts=0` and three idle threads. The `local3` trial remains installed with
the previous RPM and private state backup retained for rollback.

### GNOME versus polkit authentication

The user reports reliable fingerprint unlocking in 1Password. Audit metadata
also confirms successful `pam_fprintd` authentication through
`polkit-agent-helper-1` at 10:21:18 and 10:36:15 CET on 2026-11-17, with the same
`local3` driver process and no service restart between the failed GNOME test
and the later success. This confirms that this driver can still recognize the
existing enrollment; it does not prove that every scan or resume succeeds.
[1Password documents its use of polkit and PAM](https://support.1password.com/system-authentication-linux-security/).

On this Fedora installation, vendor `polkit-1` includes `system-auth`, whereas
`gdm-fingerprint` uses the separate `fingerprint-auth` stack. Both reach the same
`open-fprintd` and `python-validity` daemons. Neither PAM stack was changed for
the fork trial.

The broker's precise timestamps for another failed GNOME unlock show
`VerifyStart` at 10:34:57.410964, client disconnection/`do_release` at
10:34:57.436411, and a new `VerifyStart` at 10:34:57.590145. That is about 154 ms
between release and restart. At password unlock at 10:35:12, the backend logged
two cancellations. This is consistent with the known backend worker race, not
proof of a generally defective reader or a 1Password window holding the device.
Further diagnosis should correlate scan lifetimes and sanitized error categories
without enabling raw USB/TLS debug output. Do not reset calibration, erase
enrollment, or weaken PAM based on these symptoms.

On 2026-11-17 a temporary runtime-only launch wrapper recorded scan IDs, active
scan counts, interrupt categories and sanitized error categories. It did not
enable raw transport debugging or change operation arguments/results, and its
seven hardware-free tests passed. Its output was limited to 15 minutes/1,200
events; a transient timer removes the launch override after 15 minutes without
interrupting an active scan. No RPM files, PAM rules or enrollment were changed.

The 10:57 test confirmed the race on real hardware: cancellation was requested
at 10:57:05.889, the first scan entered `wait_int` with cancellation still set at
10:57:05.925, and the second scan started at 10:57:06.042 while the first was
still active. The second scan repeatedly received a finger event where a start
event was expected, while the first consumed the other scan's start/completion
events. Both workers ended only on the later cancellation at 10:57:36.

A subsequent single scan completed capture at 10:57:41 but failed during
identification with USB error 19 at 10:57:42. The kernel independently recorded
an actual disconnect/re-enumeration of `06cb:009a` at the same time. The backend
then exited with status 0, leaving `python3-validity` inactive: `Restart=on-failure`
does not restart it after this clean exit. Thus an active broker can delay new
requests even though the physical reader has reappeared. The disconnect's cause
is not established; do not infer a hardware defect or permanent fingerprint
loss from it.

The user reported that 1Password no longer worked after the test. Reverting the
temporary launch override and starting both daemons was prepared, but the
administrator authentication dialog was dismissed before the recovery ran.
At that check the backend was still inactive; do not report the reader as
restored until the administrator action and device health check succeed.
On the user's retry, administrator authentication succeeded and recovery ran
at 11:03 CET. The temporary launch override and cleanup timer were disabled,
both daemons started with their packaged commands and `NRestarts=0`, and
`fprintd-list michal` again returned the original right-index enrollment.
The persistent calibration checksum was unchanged. The user then confirmed
that fingerprint unlocking in 1Password worked again. This does not verify a
fix for the GNOME cancellation race.
After a real logout/application restart, 1Password may separately require its
account password once before biometric unlocking is available again, as
[documented by 1Password](https://support.1password.com/system-authentication-linux/).

### GNOME lifecycle-guard workaround trial (2026-11-17)

[Fedora bug 2549082, comment 3](https://bugzilla.redhat.com/show_bug.cgi?id=2549082#c3)
contains a workaround for GNOME 51 starting fingerprint verification twice.
Its full version also enables initial-login fingerprints; this trial deliberately
omits that change and retains the existing new-session password policy. Only
the three guards for mechanism selection, an available username, and reader
change/reset handling are applied.

Files:

- [Overlay generator](../assets/gnome-fingerprint-guards.py).
- [User-service drop-in](../assets/gnome-fingerprint-guards.conf).
- [Runtime-only installer and rollback](../assets/gnome-fingerprint-guards-trial).
- [Hardware-free tests](../tests/test_gnome_fingerprint_guards.py).

The actual service on this laptop is `org.gnome.Shell@user.service`, not the
non-instantiated service assumed by the original workaround. Install only a
per-user runtime drop-in for that instance; do not change the GDM greeter or
install the global `/etc/systemd/user` workaround for this unlock-only test.
The installed JS resource is pinned by SHA-256
`3b0c729d4993f2d41e19f7a5e7b6436b7bf0226fec84f75929679934ee9d9952`.
Unknown source/failed extraction removes the old overlay so GLib uses the
packaged resource; the preparatory command cannot prevent GNOME from starting.
Do not disable this fallback or silently patch an updated GNOME version.

Run as the desktop user, **without sudo**:

```bash
python3 tests/test_gnome_fingerprint_guards.py -v
bash assets/gnome-fingerprint-guards-trial enable
```

All 17 tests passed on the installed GNOME 51.1 source, including JS syntax,
an initial-selection sequence with two starts before/one after the patch,
password/credential-manager paths, preservation of the new-login guard, and
fallback on changed source/extraction failures. An isolated GLib lookup also
loaded the generated overlay correctly. These are not real screen-unlock tests.

The trial was prepared on this laptop at 12:08 CET with the original GNOME
process still running. Backup files and the helper are private under
`/run/user/1000/t480-gnome-fingerprint-trial/`; the drop-in is under
`/run/user/1000/systemd/user/org.gnome.Shell@user.service.d/`. User lingering was
already enabled, so runtime files survive logout. Disabling/re-arming the
drop-in and unit verification were tested without restarting GNOME. Both
fingerprint daemon PIDs were unchanged. No RPM, PAM, enrollment, calibration,
GDM configuration, or 1Password settings were modified.

Activation requires a new GNOME process. Save work and **log out, then log in
with the password**; only then test Super+L and the enrolled finger without
suspending. Do not restart GDM/GNOME remotely or automatically: this would end
the active Wayland desktop and could lose unsaved work. A reboot removes the
runtime-only trial instead of activating it.

The user activated it by logging out and back in at 12:44 CET, and then
confirmed a successful Super+L fingerprint unlock. The new GNOME process logged
the preparatory command and the actual overlay resource load. The broker recorded
only one `VerifyStart` at 12:44:27.731181, followed by completion/release at
12:44:36. The audit record confirms `pam_fprintd` success in
`gdm-session-worker`, rather than password authentication. No USB disconnect was
recorded during the test, and both fingerprint daemons retained their 11:03 PIDs
with `NRestarts=0`. A preceding test at 12:16, before the new GNOME process had
loaded the overlay, still showed the old double-start/two-cancellation failure.
This is evidence that the three frontend guards fix the observed normal-lock
scenario without changing the working backend. At that stage the workaround was
still runtime-only; it is not a general fix for every backend cancellation path.
The user later confirmed continued reliable operation and requested the permanent
configuration documented above. Do not infer exhaustive suspend/resume coverage
from this single recorded test.

To disable the trial for the next login without stopping the running desktop:

```bash
bash /run/user/1000/t480-gnome-fingerprint-trial/manage.sh disable
```

Only this trial's checksum-verified drop-in is removed. Runtime backups are
retained until reboot. An already running GNOME process keeps its loaded code
until logout; reboot clears all trial files. Do not use `systemctl --user revert`
on the entire unit, as it could remove unrelated user overrides.

### Rebuild local3

Start with the signed original Copr source RPM and signature/checksum checks from
the Python compatibility section below. It supplies the retained
`python3-validity-restart-after-resume.service`, not the fork's Python code.
In a separate build directory, put that RPM as `original-source.rpm`, the pinned
archive as `fork-source.tar.gz`, and the tracked spec as `python-validity.spec`.
Verify the archive checksum above before proceeding. In the Fedora 45 build
container, with that directory mounted as `/build`, run:

```bash
dnf install -y rpm-build dnf5-plugins patch
rpm --define "_topdir /build/rpmbuild" -i /build/original-source.rpm
install -m 0644 /build/python-validity.spec /build/rpmbuild/SPECS/python-validity.spec
install -m 0644 /build/fork-source.tar.gz /build/rpmbuild/SOURCES/960b44bda3781b317272211e73856b5a9b0fb0e4.tar.gz
dnf builddep -y /build/rpmbuild/SPECS/python-validity.spec
rpmbuild --define "_topdir /build/rpmbuild" -ba /build/rpmbuild/SPECS/python-validity.spec
```

The spec intentionally does not apply Copr's restart-always patch: the fork has
its own delayed, rate-limited restart policy and does not enable raw USB/TLS
debugging by default. It retains an existing T480 firmware file instead of
downloading it again on every RPM upgrade. It does not enable an additional
resume workaround or change PAM.

### Preserve state before a host trial

Stop and temporarily runtime-mask both fingerprint daemons before copying state
or installing the RPM, so udev/DBus cannot start the driver mid-migration.
Keep a root-only backup of `/run/python-validity`, `/etc/python-validity`, any
existing `/var/lib/python-validity`, and the previous `local1` RPM. Backups and
calibration must remain outside the Git repository. On this laptop the trial
backup is `/var/lib/t480-validity-local3-backup.nXjVbnr3` (root-only).

Copy the existing `calib-data.bin` and
`6_07f_lenovo_mis_qm.xpfwext` unchanged into `/var/lib/python-validity/`, owned by
root with a 0700 directory and 0600 files. Refuse to overwrite a different
pre-existing persistent calibration. Check the copies with `cmp -s`; do not
print their contents. Restore normal SELinux labels with `restorecon`.
Do not factory-reset, format the sensor flash, or re-enroll fingerprints for
this migration. USB transport reset/re-open during normal driver recovery is
not a factory reset.

Install the local RPM, unmask the two daemons, and start them. Verify both
service state and actual `fprintd-list`/`fprintd-verify` results; an active daemon
is not sufficient. Real GNOME unlock and suspend/resume results must be recorded
separately. At this stage, the existing sleep hook and `open-fprintd` package are
unchanged.

For rollback, stop/mask the daemons first and install the retained `local1` RPM.
Its state path is `/run/python-validity`: if a reboot has removed that directory,
restore the preserved calibration and firmware there with private permissions
before starting the old driver. Never regenerate calibration or erase
enrollments merely to roll the package back. Leave the private backups intact.

### Existing upstream candidates (checked 2026-11-16)

- [PR #296: Rewrite for Fedora 45](https://github.com/uunicorn/python-validity/pull/296),
  opened 2026-11-15, reports working lock-screen authentication on a Fedora 45
  T480s with KDE. Its small diff changes RPM macros/version, build helpers, and
  firmware-path normalization; it does not change scan cancellation or GNOME
  integration. It was still open and unmerged when checked.
- [PR #290: sensor recovery and quieter logs](https://github.com/uunicorn/python-validity/pull/290)
  and [open-fprintd PR #30](https://github.com/uunicorn/open-fprintd/pull/30)
  cover USB re-acquisition, bounded initialization recovery, and in-process
  sleep/resume handling. The author's
  [validation notes](https://github.com/alhasapi/python-validity-fix)
  report two reboots and fourteen suspend/resume cycles on `06cb:009a` under an
  Arch-based system. These are candidates for review, not a confirmed Fedora 45
  GNOME fix or a released upstream solution.
- [PR #217: USB timeout and scan-failure handling](https://github.com/uunicorn/python-validity/pull/217)
  reports screen-lock testing, but its current branch also changes enrollment
  database handling and adds input monitoring. Do not install the entire branch
  merely to fix cancellation; review and test any relevant changes separately.

The existing USB reader already had `power/persist=1` during this investigation,
so applying the commonly suggested persistence rule again would not change its
current setting. No third-party installer from these candidates was executed.

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

The tested upgrade package (`local1`) changes only the RPM release and changelog;
the driver Python source is unchanged. Its spec patch is
[assets/python-validity-fedora45.patch](../assets/python-validity-fedora45.patch).
The separate `local2` cancellation experiment above is not used by this recipe.
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
    patch --batch --forward --fuzz=0 -p0 < /build/python-validity-fedora45.patch
    rpmbuild --define "_topdir /build/rpmbuild" -ba python-validity.spec
    dnf install -y /build/rpmbuild/RPMS/noarch/python3-validity-0.15-1.fc45.local1.noarch.rpm
    dnf check
    python3 -c "import validitysensor, dbus, usb, yaml, cryptography"
  '
```

Run Podman as the desktop user. The container installs build dependencies in its
own filesystem. Stop if the source checksum or signature check fails; a missing
Copr signing key needs to be resolved before continuing.

The originally tested `local1` binary RPM had SHA-256
`9453ccb7e4f7b1c8e369580f93e062c26b3a76b5a10bb1de2af9a898aad53b08`.
This identifies that particular build, not a reproducible hash for future builds.
Validation included dependency checks, importing all 23 driver modules under
Python 3.15, and recognizing the existing enrolled finger on the real sensor
using the Fedora 45 environment. The new host's screen unlock was then verified.

The `local2` binary built on 2026-11-16 has SHA-256
`3e8d0732fddfa15b8520b3a2f18b6e7767bc8676480acd8ff0bc1dac06a30924`;
the corresponding source RPM has SHA-256
`70264e7e87388dd33472084656605d9fd8c36a0119d9eca82c2d2ef5f0dd6b2e`.

RPM binaries, sensor state, biometric templates, and local configuration backups
are not stored in this repository. Build outputs are ignored by Git.

### Reproduce the cancellation experiment in a container

This is for further debugging, not a recommended host upgrade: the physical
GNOME unlock test failed. Keep the upgrade recipe above on `local1`.
For an experimental `local2` build, use a separate build directory and copy the
signed original source RPM, the
[experimental spec patch](../assets/python-validity-cancellation-rpm.patch),
the scan patch, and the regression test into its `/build` volume. In the same
Fedora 45 build environment with build dependencies installed, run:

```bash
rpm --define "_topdir /build/rpmbuild" -i /build/python-validity-0.15-1.fc44.src.rpm
cd /build/rpmbuild/SPECS
patch --batch --fuzz=0 -p0 < /build/python-validity-cancellation-rpm.patch
install -m 0644 /build/python-validity-serialize-scans.patch /build/rpmbuild/SOURCES/
rpmbuild --define "_topdir /build/rpmbuild" -ba python-validity.spec
dnf install -y /build/rpmbuild/RPMS/noarch/python3-validity-0.15-1.fc45.local2.noarch.rpm
dnf check
install -D -m 0644 /usr/lib/python3.15/site-packages/validitysensor/usb.py /tmp/installed-source/validitysensor/usb.py
install -m 0644 /usr/lib/python-validity/dbus-service /tmp/installed-source/dbus-service
python3 /build/test_python_validity_cancellation.py --source-root /tmp/installed-source -v
```

The experimental spec patch replaces, rather than follows, the `local1` spec
patch. An original driver failing eight regression cases is expected and is not
a reason to force-deploy this experimental package. If it has been installed on
a host, downgrade using the retained `local1` RPM and restart the service:

```bash
sudo dnf downgrade /path/to/python3-validity-0.15-1.fc45.local1.noarch.rpm
sudo systemctl restart python3-validity.service
```

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
