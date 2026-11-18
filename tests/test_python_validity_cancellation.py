"""Run real driver methods against a mock transport, without opening a sensor."""
import argparse
import ast
import errno
import logging
import threading
import time
import unittest
from binascii import hexlify
from pathlib import Path
from types import SimpleNamespace


class Cancelled(Exception):
    pass


class PollTimeout(Exception):
    errno = errno.ETIMEDOUT


class OperationStillRunning(Exception):
    pass


def extract(path, original_name, name, wanted, namespace):
    tree = ast.parse(path.read_text())
    original = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == original_name)
    methods = [node for node in original.body if isinstance(node, ast.FunctionDef) and node.name in wanted]
    for node in methods:
        node.decorator_list = []
    module = ast.Module(body=[ast.ClassDef(name=name, bases=[], keywords=[], body=methods, decorator_list=[])], type_ignores=[])
    exec(compile(ast.fix_missing_locations(module), str(path), "exec"), namespace)
    return namespace[name]


class MockTransport:
    def __init__(self):
        self.first_read = threading.Event()
        self.force_stop = threading.Event()
        self.match = threading.Event()
        self.read_count = 0
        self.cancel_on_read = None

    def read(self, *_args, **_kwargs):
        self.read_count += 1
        self.first_read.set()
        if self.force_stop.is_set():
            raise Cancelled()
        if self.cancel_on_read:
            self.cancel_on_read()
            return b"\x03"
        if self.match.wait(0.01):
            return b"\x03"
        raise PollTimeout()


class MockSensor:
    def __init__(self, usb):
        self.usb = usb
        self.before_poll = threading.Event()
        self.before_poll.set()
        self.started = threading.Condition()
        self.release_unresponsive = threading.Event()
        self.unresponsive = False
        self.late_result = False
        self.active = 0
        self.maximum_active = 0
        self.starts = 0
        self.user_id = 1

    def cancel(self):
        self.usb.cancel = True

    def wait_for_starts(self, count):
        with self.started:
            return self.started.wait_for(lambda: self.starts >= count, timeout=1)

    def identify(self, update):
        with self.started:
            self.starts += 1
            self.active += 1
            self.maximum_active = max(self.maximum_active, self.active)
            self.started.notify_all()
        try:
            if self.unresponsive:
                if not self.release_unresponsive.wait(2):
                    raise RuntimeError("Mock operation was not released")
            else:
                if not self.before_poll.wait(2):
                    raise RuntimeError("Mock operation did not enter USB polling")
                try:
                    self.usb.wait_int()
                except Cancelled:
                    if not self.late_result:
                        raise
                    update(RuntimeError("Late retry from cancelled operation"))
            return self.user_id, 0, None
        finally:
            with self.started:
                self.active -= 1

    def enroll(self, _identity, _finger, update):
        self.identify(lambda error: update(None, error))


class CancellationTests(unittest.TestCase):
    def setUp(self):
        self.threads = []
        self.transport = MockTransport()
        usb_namespace = {"USBError": PollTimeout, "CancelledException": Cancelled, "errno": errno, "hexlify": hexlify}
        Usb = extract(SOURCE_ROOT / "validitysensor/usb.py", "Usb", "TestUsb", {"wait_int"}, usb_namespace)
        self.usb = Usb()
        self.usb.dev = self.transport
        self.usb.trace = lambda _message: None
        self.usb.cancel = False
        self.sensor = MockSensor(self.usb)
        owner = self

        class TrackedThread(threading.Thread):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                owner.threads.append(self)

        methods = {"VerifyStart", "Cancel", "EnrollStart", "_stop_operation", "_prepare_operation", "_start_worker"}
        namespace = {
            "Thread": TrackedThread, "Event": threading.Event, "sensor": self.sensor,
            "usb": self.usb, "logging": logging, "NoEnrolledPrints": RuntimeError,
            "CancelledException": Cancelled, "OperationStillRunning": OperationStillRunning,
            "usb_core": SimpleNamespace(USBError=PollTimeout), "loop": SimpleNamespace(quit=lambda: None),
            "finger_ids": {"right-index-finger": 7},
        }
        driver_path = SOURCE_ROOT / "dbus-service"
        if not driver_path.exists():
            driver_path = SOURCE_ROOT / "dbus_service/dbus-service"
        Driver = extract(driver_path, "Device", "TestDriver", methods, namespace)
        self.driver = Driver()
        self.driver.STOP_TIMEOUT = 0.1
        self.driver._worker = None
        self.driver._cancelled = threading.Event()
        self.driver.user2record = lambda _user: SimpleNamespace(dbid=1)
        self.driver.user2identity = lambda _user: "mock-identity"
        self.driver.VerifyFingerSelected = lambda _finger: None
        self.statuses = []
        self.driver.VerifyStatus = lambda result, done: self.statuses.append((result, done))
        self.driver.EnrollStatus = lambda result, done: self.statuses.append((result, done))

    def tearDown(self):
        self.sensor.cancel()
        self.transport.force_stop.set()
        self.sensor.before_poll.set()
        self.sensor.release_unresponsive.set()
        for thread in self.threads:
            thread.join(1)
        self.assertFalse(any(thread.is_alive() for thread in self.threads), "Leaked mock worker")

    def start(self):
        self.driver.VerifyStart("mock-user", "any")
        self.assertTrue(self.sensor.wait_for_starts(1))

    def test_cancel_waits_until_worker_stops(self):
        self.start()
        self.assertTrue(self.transport.first_read.wait(1))
        self.driver.Cancel()
        self.assertFalse(self.threads[-1].is_alive())

    def test_rapid_restart_has_only_one_active_scan(self):
        self.start()
        self.assertTrue(self.transport.first_read.wait(1))
        self.driver.Cancel()
        self.driver.VerifyStart("mock-user", "any")
        self.assertTrue(self.sensor.wait_for_starts(2))
        self.assertEqual(self.sensor.maximum_active, 1)

    def test_cancel_before_first_usb_poll_is_preserved(self):
        self.sensor.before_poll.clear()
        self.start()
        release = threading.Timer(0.02, self.sensor.before_poll.set)
        release.start()
        try:
            self.driver.Cancel()
            self.assertFalse(self.threads[-1].is_alive())
        finally:
            release.join()

    def test_cancelled_usb_wait_does_not_read_or_clear_cancellation(self):
        self.usb.cancel = True
        self.transport.force_stop.set()
        with self.assertRaises(Cancelled):
            self.usb.wait_int()
        self.assertEqual(self.transport.read_count, 0)
        self.assertTrue(self.usb.cancel)

    def test_cancellation_during_read_discards_returned_packet(self):
        self.transport.cancel_on_read = lambda: setattr(self.usb, "cancel", True)
        with self.assertRaises(Cancelled):
            self.usb.wait_int()

    def test_cancelled_scan_drops_late_retry_and_match(self):
        self.sensor.late_result = True
        self.start()
        self.assertTrue(self.transport.first_read.wait(1))
        self.driver.Cancel()
        self.threads[-1].join(1)
        self.assertEqual(self.statuses, [])

    def test_stuck_worker_times_out_and_blocks_replacement(self):
        self.sensor.unresponsive = True
        self.start()
        before = time.monotonic()
        with self.assertRaises(OperationStillRunning):
            self.driver.Cancel()
        self.assertLess(time.monotonic() - before, 0.5)
        with self.assertRaises(OperationStillRunning):
            self.driver.VerifyStart("mock-user", "any")
        self.assertEqual(self.sensor.starts, 1)
        self.assertTrue(self.usb.cancel)

    def test_matching_user_still_succeeds(self):
        self.transport.match.set()
        self.start()
        self.threads[-1].join(1)
        self.assertEqual(self.statuses, [("verify-match", True)])

    def test_different_user_still_fails(self):
        self.sensor.user_id = 999
        self.transport.match.set()
        self.start()
        self.threads[-1].join(1)
        self.assertEqual(self.statuses, [("verify-no-match", True)])

    def test_enrollment_waits_for_verification_to_stop(self):
        self.start()
        self.assertTrue(self.transport.first_read.wait(1))
        self.driver.EnrollStart("mock-user", "right-index-finger")
        self.assertTrue(self.sensor.wait_for_starts(2))
        self.assertEqual(self.sensor.maximum_active, 1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    options, remaining = parser.parse_known_args()
    SOURCE_ROOT = options.source_root
    logging.disable(logging.CRITICAL)
    unittest.main(argv=[__file__, *remaining])
