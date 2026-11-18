"""Test real GNOME methods without starting a compositor or claiming a reader."""
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("fingerprint_guards", REPO / "assets/gnome-fingerprint-guards.py")
guards = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guards)


class GuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = guards.load_source()
        cls.patched = guards.patch_source(cls.original)
        cls.node = shutil.which("node")
        if not cls.node:
            raise unittest.SkipTest("Node.js is required for hardware-free JavaScript checks")

    def run_methods(self, assertions, source=None):
        source = self.patched if source is None else source
        names = ["_handleSelectMechanism", "_handleCanStartService", "_onFingerprintChanged"]
        methods = []
        for name in names:
            match = re.search(rf"^    {name}\([^\n]*\) \{{\n.*?^    \}}", source, re.M | re.S)
            self.assertIsNotNone(match)
            methods.append(match.group())
        script = """
import assert from 'node:assert/strict';
const FINGERPRINT_SERVICE_NAME = 'gdm-fingerprint';
const Role = {FINGERPRINT: 'fingerprint'};
const methods = ({METHODS});
function fresh() {
    return Object.assign({
        _selectedMechanism: null, _userName: 'test-user',
        _enabledMechanisms: [{serviceName: FINGERPRINT_SERVICE_NAME}],
        _enabledRoles: [Role.FINGERPRINT], _credentialManagers: {},
        _hasAnyCredentialManagerToken: () => false,
        _updateEnabledMechanisms() { this.updated = true; },
        events: [], emit(...args) { this.events.push(args); },
    }, methods);
}
ASSERTIONS
""".replace("METHODS", ",\n".join(methods)).replace("ASSERTIONS", assertions)
        return subprocess.run([self.node, "--input-type=module"], input=script, text=True,
                              capture_output=True, check=False)

    def check_methods(self, assertions):
        result = self.run_methods(assertions)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_full_resource_parses(self):
        result = subprocess.run([self.node, "--check", "--input-type=module"], input=self.patched,
                                text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_original_reproduces_early_start(self):
        code = "assert.equal(Boolean(fresh()._handleCanStartService(FINGERPRINT_SERVICE_NAME)), false);"
        self.assertNotEqual(self.run_methods(code, self.original).returncode, 0)

    def test_wait_for_mechanism_before_fingerprint(self):
        self.check_methods("assert.equal(Boolean(fresh()._handleCanStartService(FINGERPRINT_SERVICE_NAME)), false);")

    def test_selection_sequence_starts_fingerprint_once(self):
        sequence = "const c=fresh(); let starts=0; if(c._handleCanStartService(FINGERPRINT_SERVICE_NAME)) starts++; c._selectedMechanism={serviceName:'gdm-password'}; c._handleSelectMechanism(); if(c._handleCanStartService(FINGERPRINT_SERVICE_NAME)) starts++;"
        original = self.run_methods(sequence + "assert.equal(starts,2);", self.original)
        self.assertEqual(original.returncode, 0, original.stderr)
        self.check_methods(sequence + "assert.equal(starts,1);")

    def test_selected_password_still_allows_parallel_fingerprint(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; assert.ok(c._handleCanStartService(FINGERPRINT_SERVICE_NAME));")

    def test_disabled_fingerprint_stays_disabled(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; c._enabledMechanisms=[]; assert.ok(!c._handleCanStartService(FINGERPRINT_SERVICE_NAME));")

    def test_no_username_does_not_start_fingerprint(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; c._userName=null; assert.ok(!c._handleCanStartService(FINGERPRINT_SERVICE_NAME));")

    def test_no_username_selection_does_not_reset(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; c._userName=null; c._handleSelectMechanism(); assert.deepEqual(c.events,[]);")

    def test_selected_user_still_resets(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; c._handleSelectMechanism(); assert.deepEqual(c.events,[['reset',{softReset:true}]]);")

    def test_reader_change_without_username_updates_without_reset(self):
        self.check_methods("const c=fresh(); c._userName=null; c._onFingerprintChanged(); assert.equal(c.updated,true); assert.deepEqual(c.events,[]);")

    def test_reader_change_with_user_keeps_reset(self):
        self.check_methods("const c=fresh(); c._onFingerprintChanged(); assert.deepEqual(c.events,[['reset',{softReset:true,reuseEntryText:true}]]);")

    def test_password_and_credential_manager_paths_are_unchanged(self):
        self.check_methods("const c=fresh(); c._selectedMechanism={serviceName:'gdm-password'}; assert.equal(c._handleCanStartService('gdm-password'),true); c._hasAnyCredentialManagerToken=()=>true; c._credentialManagers.external={token:'test-token'}; assert.equal(c._handleCanStartService('external'),true);")

    def test_new_login_policy_is_preserved(self):
        guard = "    _connectFingerprintManager() {\n        if (!this._reauthOnly)\n            return;"
        self.assertIn(guard, self.original)
        self.assertIn(guard, self.patched)

    def test_unknown_source_and_double_patching_are_rejected(self):
        for source in [self.original + "\n", self.patched]:
            with self.assertRaises(guards.UnsupportedSource):
                guards.patch_source(source)

    def test_unknown_source_removes_stale_overlay(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "authServicesLegacy.js"
            target.write_text("stale content")
            self.assertFalse(guards.prepare(directory, loader=lambda: "unknown source"))
            self.assertFalse(target.exists())

    def test_loader_failure_does_not_reuse_stale_overlay(self):
        def fail():
            raise RuntimeError("extraction failed")
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "authServicesLegacy.js"
            target.write_text("stale content")
            self.assertFalse(guards.prepare(directory, loader=fail))
            self.assertFalse(target.exists())

    def test_prepare_generates_only_reviewed_resource(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(guards.prepare(directory, loader=lambda: self.original))
            self.assertEqual((Path(directory) / "authServicesLegacy.js").read_text(), self.patched)


if __name__ == "__main__":
    unittest.main()
