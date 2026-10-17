#!/usr/bin/env python3
"""Host safety gates, no ADB/device operations. Actual phone evidence is separate."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from run_android_physical_qa import PhysicalRun, ROOT, loopback, require


class PhysicalSafetyTests(unittest.TestCase):
    def run_config(self):
        return PhysicalRun("SYNTHETIC123","Synthetic-Samsung","http://127.0.0.1:8798",ROOT/"qa/results/android-phase-c/host-safety")

    def test_only_explicit_loopback_without_path_credentials_or_query(self):
        self.assertEqual(8798,loopback("http://127.0.0.1:8798").port)
        for origin in ["https://relay.example.invalid","http://localhost:8798","http://127.0.0.1:80","http://127.0.0.1:8798/","http://127.0.0.1:8798/?x=1","http://a@127.0.0.1:8798","http://127.0.0.1:8798#x"]:
            with self.subTest(origin=origin),self.assertRaises(ValueError):loopback(origin)

    def test_emulator_or_outside_artifact_root_fails_before_adb(self):
        with self.assertRaises(ValueError):PhysicalRun("emulator-5554","Samsung","http://127.0.0.1:8798",ROOT/"qa/results/android-phase-c/safety")
        with tempfile.TemporaryDirectory() as tmp,self.assertRaises(ValueError):PhysicalRun("SYNTHETIC123","Samsung","http://127.0.0.1:8798",Path(tmp))

    def test_wrong_model_and_unauthorized_device_cannot_install(self):
        run=self.run_config()
        with patch.object(run,"adb",return_value=subprocess.CompletedProcess([],0,b"unauthorized\n",b"")) as call:
            with self.assertRaisesRegex(RuntimeError,"offline or unauthorized"):run.install()
            self.assertEqual(1,call.call_count)
        with patch.object(run,"adb",side_effect=[subprocess.CompletedProcess([],0,b"device\n",b""),subprocess.CompletedProcess([],0,b"Wrong phone\n",b"")]) as call:
            with self.assertRaisesRegex(RuntimeError,"Unexpected phone"):run.install()
            self.assertEqual(2,call.call_count)

    def test_only_reviewed_test_namespace_can_run(self):
        run=self.run_config()
        args=run.args("com.together.android.BusinessUiTest#actualFinanceCRUDCurrencyBillsAndReviewUseOneLedger")
        self.assertEqual("com.together.android.debug.test/com.together.android.IsolatedAndroidTestRunner",args[-1])
        self.assertIn("explicit-test-app-only",args)
        for invalid in ["android.other.Test","com.together.android.Test;reboot","com.together.android.Test #test"]:
            with self.subTest(invalid=invalid),self.assertRaises(RuntimeError):run.args(invalid)

    def test_fail_closed_checks_survive_optimized_python(self):
        # Explicit exceptions, not Python assert statements, guard identity/package/origin.
        with self.assertRaises(RuntimeError):require(False,"guard")


if __name__=="__main__":unittest.main()
