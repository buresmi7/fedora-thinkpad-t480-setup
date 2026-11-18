"""Exercise the installer in private fixtures; never call the real user manager."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.geteuid() == 0, "the user-only installer intentionally rejects root")
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="t480-gnome-install-test-")
        self.root = Path(self.temporary.name)
        self.desktop = self.root / "desktop"
        self.runtime = self.root / "runtime"
        self.binary = self.root / "bin"
        for directory in [self.desktop, self.runtime, self.binary]:
            directory.mkdir(mode=0o700)
        self.env = os.environ.copy()
        self.env.pop("XDG_CONFIG_HOME", None)
        self.env.pop("G_RESOURCE_OVERLAYS", None)
        self.env.update({
            "PATH": str(self.binary) + os.pathsep + self.env["PATH"],
            "T480_FIXTURE_HOME": str(self.desktop),
            "T480_FIXTURE_RUNTIME": str(self.runtime),
            "T480_FIXTURE_LOG": str(self.root / "commands.log"),
        })
        self.command("getent", 'printf "fixture:x:1000:1000:fixture:%s:/bin/bash\\n" "$T480_FIXTURE_HOME"\n')
        self.command("loginctl", 'printf "%s\\n" "$T480_FIXTURE_RUNTIME"\n')
        self.command("systemctl", '''
printf '%s\\n' "$*" >> "$T480_FIXTURE_LOG"
case "$*" in
  *show-environment*) exit 0 ;;
  *--property=MainPID*) printf '4242\\n' ;;
  *--property=Environment*) printf '%s\\n' "${T480_FIXTURE_OVERLAY:-}" ;;
  *daemon-reload*)
    if [[ ${T480_FIXTURE_FAIL_RELOAD:-0} == 1 && ! -e $T480_FIXTURE_RUNTIME/reload-failed ]]; then
      touch "$T480_FIXTURE_RUNTIME/reload-failed"
      exit 1
    fi ;;
esac
''')
        self.installer = REPO / "assets/gnome-fingerprint-guards-install"
        self.dropin = self.desktop / ".config/systemd/user/org.gnome.Shell@user.service.d/90-t480-fingerprint-guards.conf"
        self.trial = self.runtime / "systemd/user/org.gnome.Shell@user.service.d/90-t480-fingerprint-guards.conf"
        self.installed = self.desktop / ".local/libexec/t480-gnome-fingerprint"

    def tearDown(self):
        self.temporary.cleanup()

    def command(self, name, body):
        path = self.binary / name
        path.write_text("#!/bin/bash\nset -e\n" + body)
        path.chmod(0o700)

    def run_installer(self, action="enable", script=None, success=True):
        result = subprocess.run(["/usr/bin/bash", str(script or self.installer), action],
                                env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def create_trial(self):
        self.trial.parent.mkdir(parents=True)
        shutil.copyfile(REPO / "assets/gnome-fingerprint-guards.conf", self.trial)
        self.env["T480_FIXTURE_OVERLAY"] = "G_RESOURCE_OVERLAYS=/org/gnome/shell/gdm/authServicesLegacy.js=" + str(self.runtime / "t480-gnome-fingerprint-trial/authServicesLegacy.js")

    def test_fresh_install_is_persistent_and_private(self):
        self.run_installer()
        self.assertEqual(self.dropin.read_bytes(), (REPO / "assets/gnome-fingerprint-guards-persistent.conf").read_bytes())
        self.assertEqual(self.installed.stat().st_mode & 0o777, 0o700)
        self.assertTrue((self.installed / "manage.sh").is_file())
        self.assertTrue((self.installed / "gnome-fingerprint-guards.py").is_file())
        calls = (self.root / "commands.log").read_text()
        self.assertNotIn("restart", calls)
        self.assertNotIn(" stop ", calls)
        self.assertNotIn(" start ", calls)

    def test_known_trial_is_backed_up_and_migrated(self):
        self.create_trial()
        self.run_installer()
        self.assertFalse(self.trial.exists())
        backups = list(self.desktop.glob(".local/state/fedora-t480-setup/gnome-fingerprint-backups/change.*/runtime-trial.conf.before"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), (REPO / "assets/gnome-fingerprint-guards.conf").read_bytes())

    def test_unknown_trial_is_never_overwritten(self):
        self.create_trial()
        self.trial.write_text("unrelated override")
        self.run_installer(success=False)
        self.assertEqual(self.trial.read_text(), "unrelated override")
        self.assertFalse(self.dropin.exists())

    def test_repeated_install_is_safe(self):
        self.run_installer()
        self.run_installer()
        self.assertEqual(self.dropin.read_text().count("ExecStartPre="), 1)

    def test_rollback_and_reenable_work_without_repository(self):
        self.run_installer()
        manager = self.installed / "manage.sh"
        self.run_installer("disable", script=manager)
        self.assertFalse(self.dropin.exists())
        self.assertTrue(manager.exists())
        self.run_installer(script=manager)
        self.assertTrue(self.dropin.exists())

    def test_modified_persistent_override_is_preserved(self):
        self.run_installer()
        self.dropin.write_text("user modification")
        self.run_installer("disable", success=False)
        self.assertEqual(self.dropin.read_text(), "user modification")

    def test_modified_installed_helper_is_preserved(self):
        self.run_installer()
        helper = self.installed / "gnome-fingerprint-guards.py"
        helper.write_text("user modification")
        self.run_installer(success=False)
        self.assertEqual(helper.read_text(), "user modification")

    def test_other_resource_overlay_is_not_replaced(self):
        self.env["T480_FIXTURE_OVERLAY"] = "G_RESOURCE_OVERLAYS=/different/resource=/different/file"
        self.run_installer(success=False)
        self.assertFalse(self.dropin.exists())

    def test_reload_failure_restores_original_trial(self):
        self.create_trial()
        self.env["T480_FIXTURE_FAIL_RELOAD"] = "1"
        self.run_installer(success=False)
        self.assertFalse(self.dropin.exists())
        self.assertEqual(self.trial.read_bytes(), (REPO / "assets/gnome-fingerprint-guards.conf").read_bytes())


if __name__ == "__main__":
    unittest.main()
