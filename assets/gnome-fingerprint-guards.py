#!/usr/bin/python3
"""Prepare a fail-open, per-user GNOME 51 resource overlay for a trial.

Based on the three lifecycle guards in Fedora bug 2549082 comment 3.
Deliberately retain GNOME's password-only policy for a new login session.
This helper never restarts GNOME or accesses the fingerprint device.
"""
import argparse
import ctypes
import hashlib
import os
from pathlib import Path
import sys
import tempfile


RESOURCE = "/org/gnome/shell/gdm/authServicesLegacy.js"
EXPECTED_SHA256 = "3b0c729d4993f2d41e19f7a5e7b6436b7bf0226fec84f75929679934ee9d9952"
GUARDS = (
    (
        "    _handleSelectMechanism() {\n        if (this._selectedMechanism)\n",
        "    _handleSelectMechanism() {\n        if (this._selectedMechanism && this._userName)\n",
    ),
    (
        "            this._enabledMechanisms.some(m => m.serviceName === serviceName) &&\n"
        "            this._userName);",
        "            this._enabledMechanisms.some(m => m.serviceName === serviceName) &&\n"
        "            this._selectedMechanism && this._userName);",
    ),
    (
        "        this._updateEnabledMechanisms();\n"
        "        this.emit('reset', {softReset: true, reuseEntryText: true});",
        "        this._updateEnabledMechanisms();\n"
        "        if (this._userName)\n"
        "            this.emit('reset', {softReset: true, reuseEntryText: true});",
    ),
)


class UnsupportedSource(ValueError):
    pass


def patch_source(source):
    if hashlib.sha256(source.encode()).hexdigest() != EXPECTED_SHA256:
        raise UnsupportedSource("packaged JavaScript differs from the reviewed GNOME 51.1 source")
    for old, new in GUARDS:
        if source.count(old) != 1:
            raise UnsupportedSource("guard context is missing or ambiguous")
        source = source.replace(old, new, 1)
    return source


def load_source():
    # GLib caches overlay settings. Clear them before importing GI or loading
    # libshell so a previous trial can never become our source of truth.
    os.environ.pop("G_RESOURCE_OVERLAYS", None)
    from gi.repository import Gio

    libraries = list(Path("/usr/lib64/gnome-shell").glob("libshell-*.so"))
    if len(libraries) != 1:
        raise UnsupportedSource("expected exactly one packaged libshell")
    ctypes.CDLL(str(libraries[0]))
    return Gio.resources_lookup_data(RESOURCE, Gio.ResourceLookupFlags.NONE).get_data().decode()


def prepare(directory, loader=load_source):
    directory = Path(directory)
    if not directory.is_dir() or directory.is_symlink():
        raise ValueError("the private trial directory must already exist")
    target = directory / "authServicesLegacy.js"
    # A missing overlay uses GLib's original built-in resource. Remove stale
    # output first, so extraction failures or a future upgrade cannot reuse it.
    target.unlink(missing_ok=True)
    try:
        original = loader()
        patched = patch_source(original)
    except Exception:
        print("T480-GNOME-FPRINT: overlay skipped; using the packaged GNOME resource", file=sys.stderr)
        return False
    descriptor, name = tempfile.mkstemp(prefix=".guards-", suffix=".js", dir=directory)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(patched)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print("T480-GNOME-FPRINT: prepared three lifecycle guards; new-login policy unchanged")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    options = parser.parse_args()
    prepare(options.directory)


if __name__ == "__main__":
    main()
