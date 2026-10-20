#!/usr/bin/env python3
"""Synthetic parser/security-gate checks; no ADB, network or device access."""
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_p2p_physical import (DEBUG_CERT, GateError, check_environment_proxy,
                               parse_android_network, verified_debug_signer,
                               verify_fresh_process_reopen, verify_instrumentation,
                               finish_participant_barrier, wifi_radio_state,
                               android_link_networks, verify_android_source_route,
                               verify_independent_uplink, verified_selected_paths,
                               verify_shared_uplink_relay_paths, verify_network_restoration,
                               verify_android_ready_state)


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

    def test_enabled_but_disconnected_wifi_radio_does_not_change_verified_cellular_path(self):
        radio = "Wi-Fi is enabled\nWifi is not connected\n"
        parsed = parse_android_network("Active default network: 243\n" + network_record() + network_record(244))
        self.assertEqual(wifi_radio_state(radio), "enabled")
        self.assertFalse(parsed["wifiInternetConnected"])
        self.assertEqual(parsed["defaultTransport"], "CELLULAR")

    def test_secondary_wifi_agent_is_rejected_even_when_cellular_is_default(self):
        for transport in ("WIFI", "CELLULAR|WIFI", "WIFI|CELLULAR"):
            for reverse in (False, True):
                with self.subTest(transport=transport, reversed_fields=reverse):
                    raw = ("Active default network: 243\n" + network_record() +
                           network_record(902, transport, "INTERNET&NOT_VPN&VALIDATED", reversed_fields=reverse))
                    with self.assertRaisesRegex(GateError, "Wi-Fi Internet or unclassified"):
                        parse_android_network(raw)

    def test_explicit_local_only_wifi_is_allowed_but_unknown_wifi_is_not(self):
        mobile = "Active default network: 243\n" + network_record()
        local = network_record(902, "WIFI", "LOCAL_NETWORK&VALIDATED&NOT_VPN")
        self.assertEqual(parse_android_network(mobile + local)["localOnlyWifiAgents"], 1)
        for caps in ("VALIDATED&NOT_VPN", "LOCAL_NETWORK&INTERNET&VALIDATED&NOT_VPN"):
            with self.subTest(caps=caps):
                with self.assertRaisesRegex(GateError, "Wi-Fi Internet or unclassified"):
                    parse_android_network(mobile + network_record(902, "WIFI", caps))

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


class CompletionRaceTests(unittest.TestCase):
    def test_receiver_can_finish_and_runner_verify_before_peer_link_closes(self):
        state = {"macAlive": True, "phoneFinishing": False, "phoneVerified": False}

        def finish_phone():
            self.assertTrue(state["macAlive"])
            state["phoneFinishing"] = True

        def verify_phone():
            self.assertTrue(state["phoneFinishing"])
            self.assertTrue(state["macAlive"], "Premature Mac close races the phone receiver's final read")
            state["phoneVerified"] = True

        def finish_mac():
            self.assertTrue(state["phoneVerified"], "Runner success must be verified before peer shutdown")
            state["macAlive"] = False

        finish_participant_barrier(finish_phone=finish_phone, await_verified_phone=verify_phone,
                                   finish_mac=finish_mac, await_mac=lambda: self.assertFalse(state["macAlive"]))

    def test_failed_or_skipped_phone_runner_aborts_barrier_without_releasing_mac(self):
        actions = []

        def fail_phone():
            verify_instrumentation("INSTRUMENTATION_STATUS_CODE: -3\nOK (1 test)\n")

        with self.assertRaises(GateError):
            finish_participant_barrier(finish_phone=lambda: actions.append("phone-finish"),
                                       await_verified_phone=fail_phone,
                                       finish_mac=lambda: actions.append("mac-finish"),
                                       await_mac=lambda: actions.append("mac-exit"))
        self.assertEqual(actions, ["phone-finish"])


class SelectedPathEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.direct = {"selected": True, "direct": True, "relayed": False}
        self.relay = {"selected": True, "direct": False, "relayed": True}

    def test_two_paths_on_one_endpoint_cannot_replace_missing_peer_evidence(self):
        with self.assertRaisesRegex(GateError, "Each endpoint"):
            verified_selected_paths(({"paths": [self.direct, self.direct]}, {"paths": []}), direct_only=True)

    def test_each_endpoint_must_have_a_selected_boolean_path_of_unambiguous_type(self):
        for invalid in ({"selected": "true", "direct": True, "relayed": False},
                        {"selected": True, "direct": True, "relayed": True},
                        {"selected": True, "direct": "true", "relayed": False}):
            with self.subTest(invalid=invalid):
                with self.assertRaises(GateError):
                    verified_selected_paths(({"paths": [self.direct]}, {"paths": [invalid]}), direct_only=False)

    def test_relay_fallback_cannot_pass_direct_only(self):
        pair = ({"paths": [self.direct]}, {"paths": [self.relay]})
        with self.assertRaisesRegex(GateError, "Direct-only"):
            verified_selected_paths(pair, direct_only=True)
        self.assertEqual(len(verified_selected_paths(pair, direct_only=False)), 2)

    def test_shared_uplink_relay_needs_mac_loopback_and_per_frame_evidence(self):
        phone = {"paths": [self.relay], "relayPathEveryFrameVerified": True}
        mac = {"paths": [self.relay], "loopbackQuicVerified": True, "relayPathEveryFrameVerified": True}
        self.assertEqual(len(verify_shared_uplink_relay_paths(mac, phone)), 2)
        for change in ({"loopbackQuicVerified": False}, {"relayPathEveryFrameVerified": False}, {"paths": [self.direct]}):
            with self.subTest(change=change):
                with self.assertRaises(GateError):
                    verify_shared_uplink_relay_paths({**mac, **change}, phone)
        with self.assertRaises(GateError):
            verify_shared_uplink_relay_paths(mac, {"paths": [self.direct]})
        with self.assertRaises(GateError):
            verify_shared_uplink_relay_paths(mac, {"paths": [self.relay]})


class AndroidReadinessEvidenceTests(unittest.TestCase):
    def test_awake_unlocked_and_numeric_duplicate_state_are_accepted(self):
        power = "mWakefulness=Awake\nmWakefulnessChanging=false\nmWakefulness=1\nmIsPowered=true\n"
        policy = "KeyguardServiceDelegate\n  showing=false\n  mInputRestricted=false\n"
        self.assertEqual(verify_android_ready_state(power, policy)["status"], "PASS")

    def test_powered_dozing_or_awake_locked_never_counts_as_ready(self):
        unlocked = "showing=false\nmInputRestricted=false\n"
        scenarios = (("mWakefulness=Dozing\nmIsPowered=true\nmStayOn=true\nmWakefulness=3\n", unlocked),
                     ("mWakefulness=Awake\n", "showing=true\nmInputRestricted=true\n"),
                     ("mWakefulness=Awake\nmInteractive=false\n", unlocked))
        for power, policy in scenarios:
            with self.subTest(power=power[:25], policy=policy[:20]):
                with self.assertRaisesRegex(GateError, "unlock it manually"):
                    verify_android_ready_state(power, policy)

    def test_missing_keyguard_or_only_numeric_wakefulness_fails_closed(self):
        for power, policy in (("mWakefulness=1\n", "showing=false\ninputRestricted=false\n"),
                              ("mWakefulness=Awake\n", "mKeyguardOccluded=false\n"),
                              ("mWakefulness=Awake\n", "showing=false\n")):
            with self.subTest(power=power, policy=policy):
                with self.assertRaises(GateError):
                    verify_android_ready_state(power, policy)


class NetworkRestorationEvidenceTests(unittest.TestCase):
    def test_restoring_unbound_and_prior_bound_state_both_need_explicit_confirmation(self):
        for previous in (False, True):
            with self.subTest(previouslyBound=previous):
                witness = {"previouslyBound": previous, "restored": True, "currentBindingMatchesPrevious": True}
                self.assertEqual(verify_network_restoration(witness)["status"], "PASS")

    def test_missing_or_failed_finally_witness_cannot_be_inferred_from_main_test_pass(self):
        for witness in (None, {"status": "PASS"}, {"previouslyBound": False, "restored": False, "currentBindingMatchesPrevious": True},
                        {"previouslyBound": True, "restored": True, "currentBindingMatchesPrevious": False},
                        {"previouslyBound": "false", "restored": True, "currentBindingMatchesPrevious": True}):
            with self.subTest(witness=witness):
                with self.assertRaisesRegex(GateError, "restoration is NOT VERIFIED"):
                    verify_network_restoration(witness)


def link_record(number, interface, transports, caps, addresses, routes):
    return (f"NetworkAgentInfo{{network{{{number}}} ni{{ CONNECTED }} "
            f"lp{{{{InterfaceName: {interface} LinkAddresses: [ {addresses} ] DnsAddresses: [] "
            f"Routes: [ {routes} ]}}}} nc{{[ Transports: {transports} Capabilities: {caps} ]}}}}\n")


def route_fixture(*, mobile_routes=None):
    # Numeric globally scoped addresses are synthetic test strings, never dialed.
    mobile_routes = mobile_routes or "::/0 -> fe80::1 rmnet_data0 mtu 0,2606:4700:1111::/64 -> :: rmnet_data0 mtu 0"
    raw = "Active default network: 243\n"
    raw += link_record(243, "rmnet_data0", "CELLULAR", "INTERNET&VALIDATED&NOT_VPN",
                       "2606:4700:1111::1/64", mobile_routes)
    # IMS has another ::/0. This is a different network's routing table and
    # must not invalidate a source-bound active-default-network proof.
    raw += link_record(209, "rmnet_data2", "CELLULAR", "IMS&VALIDATED&NOT_VPN",
                       "2606:4700:4444::1/64", "::/0 -> fe80::1 rmnet_data2 mtu 0")
    raw += link_record(267, "swlan0", "WIFI", "LOCAL_NETWORK&VALIDATED&NOT_VPN",
                       "192.168.44.1/24,2606:4700:2222::1/64",
                       "192.168.44.0/24 -> 0.0.0.0 swlan0 mtu 0,2606:4700:2222::/64 -> :: swlan0 mtu 0")
    return android_link_networks(raw)


class SourceBoundRouteEvidenceTests(unittest.TestCase):
    def test_distinct_public_peer_uses_selected_mobile_table_not_ims_default(self):
        proof = verify_android_source_route(route_fixture(), "2606:4700:1111::1", "2606:4700:3333::99",
            scope="independent-public", mac_gateway="192.168.10.1")
        self.assertEqual(proof["interface"], "rmnet_data0")
        self.assertEqual(proof["longestMatchPrefixLength"], 0)
        self.assertTrue(proof["peerLocalShortcutExcluded"])
        self.assertFalse(proof["kernelRouteCommandUsed"])

    def test_same_hotspot_cannot_count_as_independent_public_even_with_global_ipv6(self):
        for gateway in ("192.168.44.1", "192.168.10.1"):
            with self.subTest(gateway=gateway):
                with self.assertRaisesRegex(GateError, "Independent uplink NOT VERIFIED"):
                    verify_android_source_route(route_fixture(), "2606:4700:1111::1", "2606:4700:2222::99",
                        scope="independent-public", mac_gateway=gateway)

    def test_gateway_overlap_is_unknown_instead_of_invented_independence(self):
        with self.assertRaisesRegex(GateError, "gateway overlaps"):
            verify_independent_uplink(route_fixture(), "2606:4700:3333::99", "192.168.44.1")

    def test_local_ap_source_cannot_satisfy_public_mobile_source_proof(self):
        with self.assertRaisesRegex(GateError, "not owned by the default mobile"):
            verify_android_source_route(route_fixture(), "2606:4700:2222::1", "2606:4700:3333::99",
                scope="independent-public", mac_gateway="192.168.10.1")

    def test_explicit_hotspot_scope_needs_source_local_prefix_and_gateway(self):
        proof = verify_android_source_route(route_fixture(), "2606:4700:2222::1", "2606:4700:2222::99",
            scope="shared-hotspot", mac_gateway="192.168.44.1")
        self.assertEqual(proof["scope"], "shared-hotspot")
        self.assertEqual(proof["interface"], "swlan0")
        self.assertEqual(proof["longestMatchPrefixLength"], 64)
        self.assertFalse(proof["peerLocalShortcutExcluded"])
        for target, gateway in (("2606:4700:3333::99", "192.168.44.1"), ("2606:4700:2222::99", "192.168.10.1")):
            with self.subTest(target=target, gateway=gateway):
                with self.assertRaises(GateError):
                    verify_android_source_route(route_fixture(), "2606:4700:2222::1", target,
                        scope="shared-hotspot", mac_gateway=gateway)

    def test_missing_mobile_default_or_foreign_more_specific_route_is_rejected(self):
        scenarios = ("2606:4700:1111::/64 -> :: rmnet_data0 mtu 0",
                     "::/0 -> fe80::1 rmnet_data0 mtu 0,2606:4700:3333::/64 -> :: swlan0 mtu 0")
        for routes in scenarios:
            with self.subTest(routes=routes):
                with self.assertRaises(GateError):
                    verify_android_source_route(route_fixture(mobile_routes=routes), "2606:4700:1111::1", "2606:4700:3333::99",
                        scope="independent-public", mac_gateway="192.168.10.1")

    def test_public_relay_over_shared_uplink_preserves_mobile_source_but_is_not_independent(self):
        proof = verify_android_source_route(route_fixture(), "2606:4700:1111::1", "2606:4700:2222::99",
            scope="shared-uplink-public-relay", mac_gateway="192.168.44.1")
        self.assertEqual(proof["scope"], "shared-uplink-public-relay")
        self.assertEqual(proof["interface"], "rmnet_data0")
        self.assertTrue(proof["sharedUplinkVerified"])
        self.assertTrue(proof["directPeerRouteNotUsed"])
        self.assertTrue(proof["relayRequiredByQA"])
        # The same facts can never acquire the stronger independent-uplink claim.
        with self.assertRaises(GateError):
            verify_android_source_route(route_fixture(), "2606:4700:1111::1", "2606:4700:2222::99",
                scope="independent-public", mac_gateway="192.168.44.1")
        with self.assertRaisesRegex(GateError, "mobile default, not the AP"):
            verify_android_source_route(route_fixture(), "2606:4700:2222::1", "2606:4700:2222::99",
                scope="shared-uplink-public-relay", mac_gateway="192.168.44.1")


if __name__ == "__main__":
    unittest.main()
