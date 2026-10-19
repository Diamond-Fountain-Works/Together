#!/usr/bin/env python3
"""Synthetic parser/security-gate checks; no ADB, network or device access."""
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_p2p_physical import (DEBUG_CERT, GateError, check_environment_proxy,
                               parse_android_network, verified_debug_signer,
                               verify_fresh_process_reopen, verify_instrumentation)


def network_record(number=243, transports="CELLULAR", capabilities="INTERNET&NOT_VPN&VALIDATED", *, reversed_fields=False):
    fields = f"Transports: {transports} Capabilities: {capabilities}"
    if reversed_fields:
        fields = f"Capabilities: {capabilities} Transports: {transports}"
    return (f"NetworkAgentInfo{{network{{{number}}} ni{{MOBILE[NR] CONNECTED}} "
            f"lp{{InterfaceName: rmnet_data0 LinkAddresses: []}} nc{{[ {fields} ]}}}}\n")


class PublicNetworkGateTests(unittest.TestCase):
    def test_before_and_after_field_order_preserves_valid_mobile_evidence(self):
        for reverse in (False, True):
            with self.subTest(reversed_fields=reverse):
                parsed = parse_android_network("Active default network: 243\n" + network_record(reversed_fields=reverse))
                self.assertEqual(parsed["defaultTransport"], "CELLULAR")
                self.assertFalse(parsed["vpn"])

    def test_secondary_vpn_is_rejected_even_when_cellular_is_default(self):
        for transport in ("VPN", "CELLULAR|VPN", "VPN|WIFI"):
            for reverse in (False, True):
                with self.subTest(transport=transport, reversed_fields=reverse):
                    raw = ("Active default network: 243\n" + network_record() +
                           network_record(901, transport, "INTERNET&VALIDATED", reversed_fields=reverse))
                    with self.assertRaisesRegex(GateError, "active Android VPN"):
                        parse_android_network(raw)

    def test_missing_not_vpn_or_validation_cannot_be_inferred_from_other_records(self):
        for caps in ("INTERNET&VALIDATED", "INTERNET&NOT_VPN", "INTERNET&NOT_VPN_FAKE&VALIDATED"):
            with self.subTest(capabilities=caps):
                raw = ("Active default network: 243\n" + network_record(capabilities=caps) +
                       network_record(244, capabilities="INTERNET&NOT_VPN&VALIDATED"))
                with self.assertRaisesRegex(GateError, "validated mobile data"):
                    parse_android_network(raw)

    def test_default_record_must_be_present_unique_and_identifiable(self):
        for raw in (network_record(), "Active default network: 900\n" + network_record(),
                    "Active default network: 243\n" + network_record() + network_record()):
            with self.subTest(raw=raw[:30]):
                with self.assertRaises(GateError):
                    parse_android_network(raw)

    def test_proxy_environment_is_case_insensitive_and_no_proxy_is_not_a_tunnel(self):
        check_environment_proxy({"NO_PROXY": "127.0.0.1", "http_proxy": ""})
        for name in ("http_proxy", "HTTPS_PROXY", "All_Proxy"):
            with self.subTest(name=name):
                with self.assertRaisesRegex(GateError, "Proxy environment"):
                    check_environment_proxy({name: "http://127.0.0.1:9999", "NO_PROXY": "*"})


class InstalledSignerGateTests(unittest.TestCase):
    def test_old_and_new_tool_output_keep_one_pinned_identity(self):
        old = f"Signer #1 certificate SHA-256 digest: {DEBUG_CERT}\n"
        new = f"V2 Signer: certificate SHA-256 digest: {DEBUG_CERT}\nV3 Signer: certificate SHA-256 digest: {DEBUG_CERT}\n"
        self.assertEqual(verified_debug_signer(old), DEBUG_CERT)
        self.assertEqual(verified_debug_signer(new), DEBUG_CERT)

    def test_missing_or_second_different_signer_does_not_pass(self):
        unknown = "f" * 64
        for text in ("Verified using v2 scheme: true\n", f"Signer #1 certificate SHA-256 digest: {unknown}\n",
                     f"V2 Signer: certificate SHA-256 digest: {DEBUG_CERT}\nV3 Signer: certificate SHA-256 digest: {unknown}\n"):
            with self.subTest(text=text[:30]):
                with self.assertRaises(GateError):
                    verified_debug_signer(text)


class FreshProcessEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.checkpoint = {"count": 259, "digest": "a" * 64}
        self.original = {"processPid": 101}
        self.reopened = {"status": "PASS", "processPid": 202, "priorProcessPid": 101,
                         "checkpoint": self.checkpoint, "operationCount": 259, "networkUsed": False,
                         "identityRetained": True, "partnerPersisted": True, "tombstoneRetained": True,
                         "reopenCheckpointRetained": True, "reopenedAcknowledgementRetained": True}

    def test_new_pid_and_offline_exact_persistence_is_accepted(self):
        self.assertEqual(verify_fresh_process_reopen(self.original, self.reopened, self.checkpoint)["status"], "PASS")

    def test_same_missing_or_wrong_prior_pid_cannot_prove_process_restart(self):
        for update in ({"processPid": 101}, {"processPid": None}, {"processPid": True}, {"priorProcessPid": 999}):
            with self.subTest(update=update):
                with self.assertRaisesRegex(GateError, "NOT VERIFIED"):
                    verify_fresh_process_reopen(self.original, {**self.reopened, **update}, self.checkpoint)

    def test_rebuilt_or_redownloaded_state_is_not_offline_recovery(self):
        for update in ({"networkUsed": True}, {"checkpoint": {"count": 259, "digest": "b" * 64}},
                       {"identityRetained": False}, {"reopenedAcknowledgementRetained": False}):
            with self.subTest(update=update):
                with self.assertRaises(GateError):
                    verify_fresh_process_reopen(self.original, {**self.reopened, **update}, self.checkpoint)

    def test_instrumentation_skip_failure_and_exit_only_are_not_pass(self):
        verify_instrumentation("INSTRUMENTATION_STATUS_CODE: 0\nOK (1 test)\n")
        for text in ("OK (1 test)\n", "INSTRUMENTATION_STATUS_CODE: -3\nOK (1 test)\n",
                     "INSTRUMENTATION_STATUS_CODE: 0\nINSTRUMENTATION_STATUS_CODE: -2\nOK (1 test)\n"):
            with self.subTest(text=text[:30]):
                with self.assertRaises(GateError):
                    verify_instrumentation(text)


if __name__ == "__main__":
    unittest.main()
