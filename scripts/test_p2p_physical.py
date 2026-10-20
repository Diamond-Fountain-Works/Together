#!/usr/bin/env python3
"""Samsung <-> isolated native Mac P2P acceptance; never installs an APK.

USB transfers only allowlisted public bootstrap/contact files and diagnostic
summaries. Operation records, media, databases and private keys stay on their
originating device. No adb reverse, VPN changes, production App or Relay is used.
Artifacts are private and confined to ignored qa/results/p2p-public-* paths.
Independent public networks are required by default. Explicit shared-hotspot
scope is direct LAN interoperability only and never produces public acceptance.
Shared-uplink-public-relay requires a loopback-only Mac QUIC socket and verified
encrypted public-relay I/O; it still cannot prove independent Internet uplinks.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import ipaddress
import json
import os
import re
import signal
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.together.android.debug"
RUNNER = PACKAGE + ".test/com.together.android.IsolatedAndroidTestRunner"
TEST = "com.together.android.P2PPublicNetworkTest#signedPublicReplication"
REOPEN_TEST = "com.together.android.P2PPublicNetworkTest#reopenPersistedPublicReplica"
DEBUG_CERT = "d02df7cd7e848b78acd6325fe4d29ce4deea21d12f6901cc0e76ce8ffa97205c"
UUID_RE = r"[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}"
DIGEST_RE = r"[0-9a-f]{64}"
MAX_CONTROL = 262_144


class GateError(RuntimeError):
    """A fail-closed acceptance condition, with no private values in its text."""


def require(condition, message):
    if not condition:
        raise GateError(message)


def checked_json(raw):
    require(len(raw) <= MAX_CONTROL, "Public control-file size exceeds bounds")
    value = json.loads(raw)
    def visit(item):
        if isinstance(item, dict):
            for key, child in item.items():
                require(not re.search(r"private|password|secret|token|seed", key, re.I),
                        "Forbidden private field in public control file")
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)
    visit(value)
    return value


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def write_private(path, raw):
    tmp = path.with_name(path.name + ".driver-tmp")
    with tmp.open("wb") as f:
        os.chmod(tmp, 0o600)
        f.write(raw)
    tmp.replace(path)


def valid_base64(value, size):
    if not isinstance(value, str):
        return False
    try:
        data = base64.b64decode(value, validate=True)
        return len(data) == size and base64.b64encode(data).decode() == value
    except (ValueError, TypeError):
        return False


def descriptor(value):
    required = {"deviceId", "userId", "initialSpaceId", "publicKey", "displayName", "protocolVersion"}
    require(isinstance(value, dict) and required <= value.keys() and
            value.keys() <= required | {"initialTimeZoneIdentifier"}, "Invalid public descriptor shape")
    require(all(re.fullmatch(UUID_RE, value[k]) for k in ("deviceId", "userId", "initialSpaceId")),
            "Noncanonical descriptor UUID")
    require(valid_base64(value["publicKey"], 32) and value["protocolVersion"] == 4,
            "Protocol 4 public descriptor required")
    require(isinstance(value["displayName"], str) and len(value["displayName"].encode()) <= 512,
            "Invalid synthetic descriptor name")
    return value


def public_socket(value, *, allow_zero=False):
    """Accept numeric global IP socket hints only; no hostnames or USB/LAN hints."""
    require(isinstance(value, str) and len(value) <= 128, "Invalid socket hint")
    match = re.fullmatch(r"\[([0-9a-fA-F:]+)\]:(\d{1,5})|([0-9.]+):(\d{1,5})", value)
    if not match:
        return None
    host, port = (match.group(1), match.group(2)) if match.group(1) else (match.group(3), match.group(4))
    try:
        address = ipaddress.ip_address(host)
        return (str(address), int(port)) if address.is_global and (0 if allow_zero else 1) <= int(port) <= 65535 else None
    except ValueError:
        return None


def public_contact(value, expected, mode):
    require(isinstance(value, dict) and set(value) == {"address", "binding"}, "Invalid contact shape")
    address, binding = value["address"], value["binding"]
    require(isinstance(address, dict) and {"endpointId", "directAddresses"} <= address.keys() and
            address.keys() <= {"endpointId", "directAddresses", "relayURL"}, "Invalid contact address")
    require(isinstance(binding, dict) and set(binding) == {"body", "signature"}, "Invalid endpoint binding")
    body = binding["body"]
    require(isinstance(body, dict) and set(body) == {"version", "transport", "spaceId", "device", "endpointId", "authorizationDigest"},
            "Invalid signed endpoint-binding body")
    require(body["version"] == 1 and body["transport"] == "iroh-quic" and body["device"] == expected and
            body["endpointId"] == address["endpointId"] and re.fullmatch(DIGEST_RE, body["endpointId"]) and
            re.fullmatch(DIGEST_RE, body["authorizationDigest"]) and re.fullmatch(UUID_RE, body["spaceId"]) and
            valid_base64(binding["signature"], 64), "Invalid signed contact identity")
    require(isinstance(address["directAddresses"], list) and len(address["directAddresses"]) <= 32,
            "Too many socket hints")
    # Only routing hints change: the signed body remains byte-semantically intact.
    address["directAddresses"] = [hint for hint in address["directAddresses"] if public_socket(hint)]
    if mode == "directOnly":
        require(address.get("relayURL") is None and address["directAddresses"],
                "Direct-only public test needs a global direct socket hint on each endpoint")
    else:
        relay = address.get("relayURL")
        if relay is not None:
            from urllib.parse import urlsplit
            url = urlsplit(relay)
            require(url.scheme == "https" and url.hostname and not url.username and not url.password and
                    not url.query and not url.fragment and len(relay) <= 2048, "Invalid encrypted-relay hint")
        require(address["directAddresses"] or relay, "No public connection hint available")
    return value


def parse_android_network(raw):
    current = re.search(r"Active default network:\s*(\d+)", raw)
    require(current, "Cannot establish Android active default network")
    agents = [line for line in raw.splitlines() if "NetworkAgentInfo{network{" in line]
    selected = [line for line in agents if "NetworkAgentInfo{network{" + current.group(1) + "}" in line]
    require(len(selected) == 1, "Android default-network record is ambiguous")
    line = selected[0]
    def transports(agent):
        match = re.search(r"Transports:\s*([^\s]+)", agent)
        require(match, "Android network transport tokens are unavailable")
        return set(match.group(1).split("|"))
    transport_sets = [transports(item) for item in agents]
    require(not any("VPN" in tokens for tokens in transport_sets), "An active Android VPN network is present")
    local_wifi = 0
    for agent, tokens in zip(agents, transport_sets):
        if "WIFI" in tokens:
            caps = re.search(r"Capabilities:\s*([^\s\]]+)", agent)
            values = set(caps.group(1).split("&")) if caps else set()
            require("LOCAL_NETWORK" in values and "INTERNET" not in values,
                    "Android Wi-Fi Internet or unclassified Wi-Fi network is present")
            local_wifi += 1
    capabilities = re.search(r"Capabilities:\s*([^\s\]]+)", line)
    capability_tokens = set(capabilities.group(1).split("&")) if capabilities else set()
    require(transports(line) == {"CELLULAR"} and {"NOT_VPN", "VALIDATED"} <= capability_tokens,
            "Android default network must be validated mobile data without VPN")
    require(not re.search(r"(?:HttpProxy|ProxyInfo):\s*(?!null\b|none\b)\S+", line, re.I),
            "Android default network has a proxy")
    interface = re.search(r"InterfaceName:\s*([^\s]+)", line)
    require(interface and re.fullmatch(r"(?:rmnet|ccmni|pdp)[A-Za-z0-9_.-]*", interface.group(1)),
            "Android mobile interface is unknown or uses an unexpected transport")
    return {"defaultTransport": "CELLULAR", "validated": True, "vpn": False, "wifiInternetConnected": False,
            "localOnlyWifiAgents": local_wifi,
            "mobileInterface": interface.group(1)}


def android_link_networks(raw):
    """Parse current ConnectivityManager LinkProperties, not shell route tables."""
    # First establish active default, capabilities, absence of VPN/Internet Wi-Fi.
    parse_android_network(raw)
    default_id = re.search(r"Active default network:\s*(\d+)", raw).group(1)
    result = []
    for line in raw.splitlines():
        if not line.lstrip().startswith("NetworkAgentInfo{network{"):
            continue
        ident = re.search(r"NetworkAgentInfo\{network\{(\d+)\}", line)
        interface = re.search(r"InterfaceName:\s*([^\s]+)", line)
        transports = re.search(r"Transports:\s*([^\s]+)", line)
        caps = re.search(r"Capabilities:\s*([^\s\]]+)", line)
        links = re.search(r"LinkAddresses:\s*\[([^\]]*)\]", line)
        route_text = re.search(r"Routes:\s*\[([^\]]*)\]", line)
        require(ident and interface and transports and caps and links and route_text,
                "Android current LinkProperties is incomplete; route proof unavailable")
        addresses = []
        for item in links.group(1).split(","):
            item = item.strip()
            if item:
                try:
                    addresses.append(ipaddress.ip_interface(item))
                except ValueError:
                    raise GateError("Unrecognized LinkProperties address; route proof unavailable")
        routes = []
        for item in route_text.group(1).split(","):
            item = item.strip()
            if not item:
                continue
            route = re.fullmatch(r"(\S+/\d+)\s*->\s*\S+\s+(\S+)\s+mtu\s+\d+", item)
            require(route, "Unrecognized LinkProperties route; route proof unavailable")
            try:
                routes.append({"prefix": ipaddress.ip_network(route.group(1), strict=False), "interface": route.group(2)})
            except ValueError:
                raise GateError("Invalid LinkProperties route prefix")
        result.append({"id": ident.group(1), "default": ident.group(1) == default_id,
                       "interface": interface.group(1), "transports": set(transports.group(1).split("|")),
                       "capabilities": set(caps.group(1).split("&")), "addresses": addresses, "routes": routes})
    require(sum(item["default"] for item in result) == 1, "Default LinkProperties record must be unique")
    return result


def global_ipv6(value):
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        raise GateError("A numeric global IPv6 address is required")
    require(address.version == 6 and address.is_global, "A numeric global IPv6 address is required")
    return address


def verify_independent_uplink(networks, mac_address, mac_gateway):
    peer = global_ipv6(mac_address)
    for network in networks:
        if "LOCAL_NETWORK" not in network["capabilities"]:
            continue
        require(not any(link.version == 6 and peer in link.network for link in network["addresses"]),
                "Independent uplink NOT VERIFIED: Mac IPv6 is inside the phone's local network")
        require(not any(str(link.ip) == mac_gateway for link in network["addresses"]),
                "Independent uplink NOT VERIFIED: Mac gateway overlaps a phone local-network address")


def verify_android_source_route(networks, source, target, *, scope, mac_gateway=None):
    """CM/default-network + explicit source binding + LP longest-match proof.

    This is deliberately not represented as a privileged kernel route lookup.
    Separate networks can contain service-specific ::/0 routes (for example
    IMS); only the selected source/default network's LP is used for lookup.
    """
    source, target = global_ipv6(source), global_ipv6(target)
    if scope == "independent-public":
        verify_independent_uplink(networks, str(target), mac_gateway)
        candidates = [item for item in networks if item["default"] and item["transports"] == {"CELLULAR"}]
        require(len(candidates) == 1, "A unique default mobile LinkProperties record is required")
        chosen = candidates[0]
        require(any(link.ip == source for link in chosen["addresses"]),
                "Explicit P2P source is not owned by the default mobile interface")
        for item in networks:
            if item is chosen:
                continue
            require(not any(link.version == 6 and target in link.network for link in item["addresses"]),
                    "Public peer is reachable through another local/service link prefix")
        require(any(route["prefix"] == ipaddress.ip_network("::/0") and route["interface"] == chosen["interface"] for route in chosen["routes"]),
                "Default mobile IPv6 route is missing from LinkProperties")
    elif scope == "shared-hotspot":
        candidates = [item for item in networks if "WIFI" in item["transports"] and
                      "LOCAL_NETWORK" in item["capabilities"] and "INTERNET" not in item["capabilities"] and
                      any(link.ip == source for link in item["addresses"])]
        require(len(candidates) == 1, "Explicit hotspot source must belong to one known local-only Wi-Fi interface")
        chosen = candidates[0]
        require(any(link.version == 6 and target in link.network for link in chosen["addresses"]),
                "Shared-hotspot test needs Mac and phone on the same known IPv6 local prefix")
        require(mac_gateway and any(str(link.ip) == mac_gateway for link in chosen["addresses"]),
                "Shared-hotspot test needs the Mac default gateway to be the phone's AP address")
    elif scope == "shared-uplink-public-relay":
        candidates = [item for item in networks if item["default"] and item["transports"] == {"CELLULAR"}]
        require(len(candidates) == 1, "Public relay needs a unique mobile-default network")
        chosen = candidates[0]
        require(any(link.ip == source for link in chosen["addresses"]), "Public-relay source must belong to the mobile default, not the AP")
        require(any(route["prefix"] == ipaddress.ip_network("::/0") and route["interface"] == chosen["interface"] for route in chosen["routes"]),
                "Public-relay mobile IPv6 default route is missing")
        local = [item for item in networks if "WIFI" in item["transports"] and "LOCAL_NETWORK" in item["capabilities"] and
                 any(link.version == 6 and target in link.network for link in item["addresses"]) and
                 any(str(link.ip) == mac_gateway for link in item["addresses"])]
        require(len(local) == 1, "Explicit shared-uplink relay scope needs proven phone-hotspot topology")
        return {"mechanism": "ConnectivityManager LinkProperties + explicit mobile source bind; relay-only QA transport",
                "interface": chosen["interface"], "networkId": chosen["id"], "scope": scope,
                "kernelRouteCommandUsed": False, "sourceOwnedByInterface": True,
                "sharedUplinkVerified": True, "directPeerRouteNotUsed": True, "relayRequiredByQA": True}
    else:
        raise GateError("Unknown network acceptance scope")
    matches = [route for route in chosen["routes"] if route["prefix"].version == 6 and target in route["prefix"]]
    require(matches, "No advertised route to the selected peer")
    length = max(route["prefix"].prefixlen for route in matches)
    winners = [route for route in matches if route["prefix"].prefixlen == length]
    require(all(route["interface"] == chosen["interface"] for route in winners), "Peer route leaves the explicit source's interface")
    if scope == "shared-hotspot":
        require(length > 0, "A shared-hotspot peer needs a connected local prefix route")
    return {"mechanism": "ConnectivityManager LinkProperties + explicit native IPv6 source bind",
            "interface": chosen["interface"], "networkId": chosen["id"], "scope": scope,
            "longestMatchPrefixLength": length, "kernelRouteCommandUsed": False,
            "sourceOwnedByInterface": True, "peerLocalShortcutExcluded": scope == "independent-public"}


def wifi_radio_state(raw):
    """Informational only: an enabled but disconnected radio is not a path."""
    first = raw.splitlines()[0] if raw.splitlines() else ""
    match = re.search(r"\b(enabled|disabled)\b", first, re.I)
    return match.group(1).lower() if match else "unknown"


def check_environment_proxy(environment):
    require(not any(value for key, value in environment.items() if key.lower() in {"http_proxy", "https_proxy", "all_proxy"}),
            "Proxy environment variables must be unset for public acceptance")


def verified_debug_signer(certificates):
    # Build-tools 37 prints `V2 Signer:`, while earlier tools print `Signer #1`.
    # Several verified schemes can repeat one identity; a second identity or an
    # unrecognized/no certificate listing must still fail closed.
    found = re.findall(r"(?m)^(?:Signer #\d+|V[234] Signer):? certificate SHA-256 digest: ([a-f0-9]{64})$", certificates)
    require(set(found) == {DEBUG_CERT}, "Installed APK signer differs; never uninstall to bypass")
    return DEBUG_CERT


def verify_instrumentation(text):
    codes = [int(code) for code in re.findall(r"INSTRUMENTATION_STATUS_CODE: (-?\d+)", text)]
    require("OK (1 test)" in text and codes.count(0) == 1 and not any(code < 0 for code in codes),
            "Instrumentation did not report exactly one real passing test")


def verify_fresh_process_reopen(original, reopened, checkpoint):
    require(reopened.get("status") == "PASS" and reopened.get("checkpoint") == checkpoint and
            reopened.get("operationCount") == 259 and reopened.get("networkUsed") is False,
            "Fresh-process reopen must retain the exact 259-fact checkpoint without network")
    flags = ("identityRetained", "partnerPersisted", "tombstoneRetained", "reopenCheckpointRetained", "reopenedAcknowledgementRetained")
    require(all(reopened.get(flag) is True for flag in flags), "Fresh-process identity, fact, tombstone or ACK retention check failed")
    first, second = original.get("processPid"), reopened.get("processPid")
    require(type(first) is int and type(second) is int and first > 0 and second > 0 and
            first != second and reopened.get("priorProcessPid") == first,
            "Fresh-process restart NOT VERIFIED: original and reopened process IDs must differ")
    return {"firstProcessPid": first, "reopenedProcessPid": second, "networkUsed": False, "status": "PASS"}


def verified_selected_paths(endpoints, *, direct_only):
    require(len(endpoints) == 2, "Exactly two endpoint results are required")
    selected = []
    for endpoint in endpoints:
        current = [path for path in endpoint.get("paths", []) if path.get("selected") is True]
        require(current, "Each endpoint must report at least one selected transport path")
        require(all(type(path.get("direct")) is bool and type(path.get("relayed")) is bool and
                    path["direct"] != path["relayed"] for path in current), "A selected transport path has invalid or ambiguous type")
        if direct_only:
            require(all(path["direct"] and not path["relayed"] for path in current), "Direct-only test selected a relay or unknown path")
        selected.extend(current)
    return selected


def verify_shared_uplink_relay_paths(mac_result, phone_result):
    selected = verified_selected_paths((mac_result, phone_result), direct_only=False)
    require(all(path["relayed"] and not path["direct"] for path in selected),
            "Shared-uplink public-relay test cannot use a direct path")
    require(mac_result.get("loopbackQuicVerified") is True and mac_result.get("relayPathEveryFrameVerified") is True,
            "Mac must prove loopback-only QUIC sockets and relay selection for every application I/O")
    require(phone_result.get("relayPathEveryFrameVerified") is True,
            "Android must prove relay selection for every application I/O")
    return selected


def verify_network_restoration(value):
    require(isinstance(value, dict) and value.get("restored") is True and
            value.get("currentBindingMatchesPrevious") is True and type(value.get("previouslyBound")) is bool,
            "Android process Network binding restoration is NOT VERIFIED")
    return {"status": "PASS", "previouslyBound": value["previouslyBound"], "restored": True,
            "currentBindingMatchesPrevious": True}


def verify_android_ready_state(power, policy):
    message = ("Samsung must be awake and unlocked before QA. Please unlock it manually and keep the screen awake; "
               "the driver never wakes or unlocks the phone.")
    # Some Samsung power dumps repeat mWakefulness as a numeric per-display
    # enum. Only the explicit named global state is an affirmative witness.
    names = re.findall(r"\bmWakefulness\s*=\s*([A-Za-z]+)\b", power)
    require(names and set(names) == {"Awake"}, message)
    interactive = re.findall(r"\b(?:mIsInteractive|mInteractive)\s*=\s*(true|false)\b", power, re.I)
    require(not interactive or all(item.lower() == "true" for item in interactive), message)
    showing = re.findall(r"(?<![A-Za-z])(?:mKeyguardState\.)?(?:showing|mShowing)\s*=\s*(true|false)\b", policy)
    restricted = re.findall(r"\b(?:mKeyguardState\.)?(?:mInputRestricted|inputRestricted)\s*=\s*(true|false)\b", policy)
    require(showing and restricted and set(showing) == {"false"} and set(restricted) == {"false"}, message)
    return {"status": "PASS", "wakefulness": "Awake", "interactive": True,
            "interactiveEvidence": "explicit Wakefulness.Awake, with optional interactive flag cross-check",
            "keyguardShowing": False, "inputRestricted": False}


def finish_participant_barrier(*, finish_phone, await_verified_phone, finish_mac, await_mac):
    """Keep the Mac link alive through the phone's verified terminal teardown.

    Both participants already proved reciprocal persistence. Closing Mac first
    can race the phone's still-active receiver and turn a valid final session
    into EOF. Finish phone, check its *actual Runner outcome*, then close Mac.
    Any teardown/test error propagates; no invalid frame or EOF is suppressed.
    """
    finish_phone()
    await_verified_phone()
    finish_mac()
    await_mac()


def stop_owned(child):
    if child is None or child.poll() is not None:
        return
    # start_new_session makes this an owned process group, never a global kill.
    os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait(timeout=5)


class PhysicalP2P:
    def __init__(self, args):
        self.args = args
        require(re.fullmatch(r"[A-Za-z0-9_-]{5,80}", args.serial) and not args.serial.startswith("emulator-"),
                "Explicit authorized physical serial required")
        self.adb = [str(Path(os.environ.get("ANDROID_ADB", Path.home() / "Library/Android/sdk/platform-tools/adb"))), "-s", args.serial]
        self.run_id = uuid.uuid4().hex.upper()
        self.namespace = "QA-P2P-" + self.run_id
        self.phone_dir = "/sdcard/Android/data/" + PACKAGE + "/files/p2p/" + self.namespace
        self.output = Path(args.output).expanduser().resolve()
        relative = self.output.relative_to(ROOT / "qa/results")
        require(relative.parts and relative.parts[0].startswith("p2p-public-"), "Evidence must stay in ignored p2p-public-* QA results")
        self.output.mkdir(parents=True, exist_ok=True, mode=0o700)
        require(not any(self.output.iterdir()), "Refusing to overwrite existing acceptance evidence")
        self.output.chmod(0o700)
        self.mac_root = Path(tempfile.mkdtemp(prefix="together-p2p-public-", dir="/tmp")).resolve()
        self.mac_root.chmod(0o700)
        self.stages = []
        self.last_stage = {}

    def command(self, argv, *, timeout=20, check=True, input=None):
        result = subprocess.run(argv, capture_output=True, timeout=timeout, input=input)
        if check and result.returncode:
            raise GateError("Command failed; inspect retained private diagnostics")
        return result

    def phone(self, *args, **kwargs):
        return self.command(self.adb + list(args), **kwargs)

    def capture(self, name, argv, *, check=True):
        result = self.command(argv, check=False)
        write_private(self.output / name, result.stdout + result.stderr)
        require(not check or result.returncode == 0, "Network inspection failed; see private evidence")
        return result

    def power_state(self, label, *, require_ready):
        power = self.capture(label + "-android-power.txt", self.adb + ["shell", "dumpsys", "power"]).stdout.decode(errors="replace")
        policy = self.capture(label + "-android-window-policy.txt", self.adb + ["shell", "dumpsys", "window", "policy"]).stdout.decode(errors="replace")
        try:
            state = verify_android_ready_state(power, policy)
        except GateError as error:
            state = {"status": "NOT READY", "message": str(error), "networkFailureCause": "UNKNOWN"}
            write_private(self.output / (label + "-android-ready-state.json"), encoded(state))
            if require_ready:
                raise
            return state
        write_private(self.output / (label + "-android-ready-state.json"), encoded(state))
        return state

    def network_gate(self, label):
        reverse = self.capture(label + "-android-reverse.txt", self.adb + ["reverse", "--list"]).stdout
        require(not reverse.strip(), "ADB reverse must be absent during public-network acceptance")
        connectivity = self.capture(label + "-android-connectivity.txt", self.adb + ["shell", "dumpsys", "connectivity"]).stdout.decode(errors="replace")
        phone = parse_android_network(connectivity)
        wifi = self.capture(label + "-android-wifi.txt", self.adb + ["shell", "cmd", "wifi", "status"]).stdout.decode(errors="replace")
        # Active-agent/default-capability and per-peer mobile-route checks prove
        # the actual path. Do not ask the user to disable a disconnected radio.
        phone["wifiRadioState"] = wifi_radio_state(wifi)
        for setting in ("http_proxy", "global_http_proxy_host", "global_http_proxy_port", "global_proxy_pac_url"):
            proxy = self.capture(label + "-android-" + setting + ".txt", self.adb + ["shell", "settings", "get", "global", setting]).stdout.decode().strip()
            require(proxy in {"", "null", ":0", "0"}, "Android has a configured HTTP/PAC proxy")
        vpn = self.capture(label + "-mac-vpn.txt", ["/usr/sbin/scutil", "--nc", "list"]).stdout.decode(errors="replace")
        require(not re.search(r"\((?:Connected|Connecting|Disconnecting)\)", vpn), "A Mac VPN service is active")
        proxies = self.capture(label + "-mac-proxy.txt", ["/usr/sbin/scutil", "--proxy"]).stdout.decode(errors="replace")
        require(not re.search(r"(?:HTTP|HTTPS|SOCKS|FTP|ProxyAutoConfig|ProxyAutoDiscovery)Enable\s*:\s*[1-9]", proxies), "A Mac system proxy is enabled")
        check_environment_proxy(os.environ)
        interfaces = []
        gateway = None
        for family, flag in (("4", "-inet"), ("6", "-inet6")):
            route = self.capture(label + "-mac-route" + family + ".txt", ["/sbin/route", "-n", "get", flag, "default"], check=False)
            if route.returncode == 0:
                match = re.search(r"\binterface:\s*(\S+)", route.stdout.decode(errors="replace"))
                require(match and match.group(1) == "en0", "Mac default traffic must use Wi-Fi en0, not a VPN or USB interface")
                interfaces.append(match.group(1))
                if family == "4":
                    address = re.search(r"\bgateway:\s*(\S+)", route.stdout.decode(errors="replace"))
                    gateway = address.group(1) if address else None
        require(interfaces, "No verified Mac Wi-Fi default route")
        self.capture(label + "-mac-network-state.txt", ["/usr/sbin/scutil", "--nwi"])
        result = {"android": phone, "macDefaultInterface": "en0", "vpn": False, "systemProxy": False, "adbReverse": False,
                  "networkScope": self.args.network_scope}
        if getattr(self, "bound_sources_ready", False):
            result["scopeRouteProof"] = verify_android_source_route(android_link_networks(connectivity),
                public_socket(self.args.android_bind, allow_zero=True)[0],
                self.mac_source_address,
                scope=self.args.network_scope, mac_gateway=gateway)
        write_private(self.output / (label + "-network-summary.json"), encoded(result))
        return result

    def choose_bind_addresses(self):
        """Bind only current global Wi-Fi/mobile IPv6, never a USB/VPN route."""
        interfaces = self.capture("mac-wifi-addresses.txt", ["/sbin/ifconfig", "en0"]).stdout.decode(errors="replace")
        mac_candidates = []
        for line in interfaces.splitlines():
            match = re.search(r"\binet6\s+([0-9a-fA-F:]+)(?:%\S+)?\s", line)
            if match and "deprecated" not in line and ipaddress.ip_address(match.group(1)).is_global:
                mac_candidates.append(str(ipaddress.ip_address(match.group(1))))
        require(mac_candidates, "Mac en0 has no verified global IPv6 address")
        if self.args.mac_bind is None and self.args.network_scope != "shared-uplink-public-relay":
            self.args.mac_bind = "[" + mac_candidates[0] + "]:0"
        mac_source = (mac_candidates[0] if self.args.network_scope == "shared-uplink-public-relay" else
                      public_socket(self.args.mac_bind, allow_zero=True)[0])
        require(mac_source in mac_candidates, "Explicit Mac IPv6 bind is not owned by en0")
        self.mac_source_address = mac_source
        raw = (self.output / "before-android-connectivity.txt").read_text()
        networks = android_link_networks(raw)
        route4 = (self.output / "before-mac-route4.txt").read_text()
        gateway = re.search(r"\bgateway:\s*(\S+)", route4)
        self.mac_gateway = gateway.group(1) if gateway else None
        if self.args.network_scope in {"independent-public", "shared-uplink-public-relay"}:
            if self.args.network_scope == "independent-public":
                verify_independent_uplink(networks, mac_source, self.mac_gateway)
            sources = [link.ip for item in networks if item["default"] for link in item["addresses"] if link.version == 6 and link.ip.is_global]
        else:
            sources = [link.ip for item in networks if "WIFI" in item["transports"] and "LOCAL_NETWORK" in item["capabilities"]
                       and any(local.version == 6 and ipaddress.ip_address(mac_source) in local.network for local in item["addresses"])
                       and any(str(local.ip) == self.mac_gateway for local in item["addresses"])
                       for link in item["addresses"] if link.version == 6 and link.ip.is_global]
        require(sources, "No verified IPv6 source is available for the explicitly selected scope")
        if self.args.android_bind is None:
            self.args.android_bind = "[" + str(sources[0]) + "]:0"
        proof = verify_android_source_route(networks, public_socket(self.args.android_bind, allow_zero=True)[0],
            mac_source, scope=self.args.network_scope, mac_gateway=self.mac_gateway)
        self.bound_sources_ready = True
        write_private(self.output / "initial-source-route-proof.json", encoded(proof))
        # Retain local routing hints privately. Never print them or commit them.
        write_private(self.output / "bind-addresses.json", encoded({"mac": self.args.mac_bind, "macTopologyAddress": mac_source,
                                                                   "loopbackQuicForQA": self.args.network_scope == "shared-uplink-public-relay", "android": self.args.android_bind,
                                                                   "networkScope": self.args.network_scope}))

    def preflight(self):
        require(self.phone("get-state").stdout.strip() == b"device", "Samsung is not online and USB-authorized")
        model = self.phone("shell", "getprop", "ro.product.model").stdout.decode().strip()
        maker = self.phone("shell", "getprop", "ro.product.manufacturer").stdout.decode().strip().lower()
        require(model == "SM-S9210" and maker == "samsung" and self.phone("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1",
                "Only the explicitly authorized physical Samsung SM-S9210 may run this harness")
        self.model = model
        sdk = Path(os.environ.get("ANDROID_HOME", Path.home() / "Library/Android/sdk"))
        build_tools = sorted((sdk / "build-tools").glob("*/apksigner"), key=lambda p: tuple(int(x) for x in re.findall(r"\d+", p.parent.name)))
        require(build_tools, "Android build-tools/apksigner is required for signer validation")
        signer = build_tools[-1]
        aapt = signer.with_name("aapt2")
        records = []
        for package in (PACKAGE, PACKAGE + ".test"):
            paths = self.phone("shell", "pm", "path", package).stdout.decode().splitlines()
            base = [line.removeprefix("package:") for line in paths if line.endswith("/base.apk")]
            require(len(base) == 1 and re.fullmatch(r"/data/app/[A-Za-z0-9_~+./=\-]+/base\.apk", base[0]), "Expected installed Together Debug APK is missing or split path is unsafe")
            target = self.output / ("installed-test.apk" if package.endswith(".test") else "installed-app.apk")
            with target.open("wb") as stream:
                os.chmod(target, 0o600)
                child = subprocess.Popen(self.adb + ["exec-out", "cat", base[0]], stdout=stream, stderr=subprocess.PIPE, start_new_session=True)
                try:
                    _, error = child.communicate(timeout=60)
                    require(child.returncode == 0, "Cannot inspect installed APK")
                finally:
                    stop_owned(child)
            certificates = self.command([str(signer), "verify", "--print-certs", str(target)]).stdout.decode()
            write_private(self.output / (target.stem + "-cert.txt"), certificates.encode())
            verified_debug_signer(certificates)
            badging = self.command([str(aapt), "dump", "badging", str(target)]).stdout.decode()
            write_private(self.output / (target.stem + "-manifest.txt"), badging.encode())
            require(re.search(r"^package: name='" + re.escape(package) + r"'", badging, re.M), "Unexpected installed application ID")
            if package == PACKAGE:
                require("application-debuggable" in badging, "Only Together Debug may run this test")
            hasher = hashlib.sha256()
            with target.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    hasher.update(chunk)
            records.append({"package": package, "sha256": hasher.hexdigest(), "bytes": target.stat().st_size, "signer": DEBUG_CERT})
        uid = self.phone("shell", "cmd", "package", "list", "packages", "-U", PACKAGE).stdout.decode()
        match = re.search(r"package:" + re.escape(PACKAGE) + r" uid:(\d+)\b", uid)
        require(match, "Together Debug UID unavailable")
        self.uid = match.group(1)
        self.phone("shell", "run-as", PACKAGE, "id")
        listing = self.phone("shell", "pm", "list", "instrumentation").stdout.decode()
        require("instrumentation:" + RUNNER in listing and "(target=" + PACKAGE + ")" in listing, "Expected isolated test Runner is not installed")
        write_private(self.output / "installed-artifacts.json", encoded(records))
        return self.network_gate("before")

    def pull(self, name):
        require(name in {"descriptor.json", "signature.json", "contact.json", "result.json", "reopen-result.json", "stage.json", "error.json", "network-restoration.json"}, "Nonpublic phone file rejected")
        result = self.phone("exec-out", "run-as", PACKAGE, "cat", self.phone_dir + "/" + name, check=False, timeout=8)
        if result.returncode:
            return None
        try:
            return checked_json(result.stdout)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return None

    def push(self, name, raw, *, command_timeout=20):
        require(name in {"genesis-body.json", "authorization.json", "peer-contact.json", "finish", "abort"}, "Nonpublic phone input rejected")
        require(name not in {"finish", "abort"} or raw == b"", "QA lifecycle controls must be empty")
        require(len(raw) <= MAX_CONTROL and re.fullmatch(r"/sdcard/Android/data/com\.together\.android\.debug/files/p2p/QA-P2P-[A-F0-9]{32}", self.phone_dir), "Unsafe phone QA path")
        # adb shell joins arguments into a remote command. Quote only a wholly
        # validated constant/path, never JSON, user text, serial or a host path.
        self.phone("shell", "run-as", PACKAGE, "mkdir", "-p", self.phone_dir, timeout=command_timeout)
        script = "cat > " + self.phone_dir + "/" + name + ".driver-tmp"
        self.phone("shell", "-T", "run-as", PACKAGE, "sh", "-c", "'" + script + "'", input=raw, timeout=command_timeout)
        self.phone("shell", "run-as", PACKAGE, "mv", self.phone_dir + "/" + name + ".driver-tmp", self.phone_dir + "/" + name, timeout=command_timeout)

    def stage(self, side, value):
        if value is not None and value != self.last_stage.get(side):
            self.last_stage[side] = value
            self.stages.append({"side": side, "elapsedSeconds": round(time.monotonic() - self.started, 3), "value": value})
            write_private(self.output / "stages.json", encoded(self.stages))

    def route_hints(self, contact, side):
        networks = None
        if side == "android-to-mac":
            raw = self.capture("android-peer-route-linkproperties.txt", self.adb + ["shell", "dumpsys", "connectivity"]).stdout.decode(errors="replace")
            networks = android_link_networks(raw)
            if self.args.network_scope == "shared-uplink-public-relay":
                proof = verify_android_source_route(networks, public_socket(self.args.android_bind, allow_zero=True)[0],
                    self.mac_source_address, scope=self.args.network_scope, mac_gateway=self.mac_gateway)
                write_private(self.output / "android-public-relay-source-proof.json", encoded(proof))
                require(not contact["address"]["directAddresses"] and contact["address"].get("relayURL"),
                        "Shared-uplink public-relay contact must have relay hints only")
                return
        for index, hint in enumerate(contact["address"]["directAddresses"]):
            address, _ = public_socket(hint)
            if side == "mac-to-android":
                command = ["/sbin/route", "-n", "get", "-inet6" if ":" in address else "-inet", address]
                raw = self.capture("route-mac-peer-" + str(index) + ".txt", command).stdout.decode(errors="replace")
                require(re.search(r"\binterface:\s*en0\b", raw), "Peer socket would leave Mac through a non-Wi-Fi interface")
            else:
                proof = verify_android_source_route(networks,
                    public_socket(self.args.android_bind, allow_zero=True)[0], address,
                    scope=self.args.network_scope, mac_gateway=self.mac_gateway)
                write_private(self.output / ("route-android-peer-" + str(index) + ".json"), encoded(proof))

    def local_json(self, name):
        path = self.mac_root / name
        if not path.exists():
            return None
        return checked_json(path.read_bytes())

    def run(self):
        self.started = time.monotonic()
        native = instrument = logger = reopen_native = reopen_instrument = None
        result = {"status": "FAIL", "direction": self.args.direction, "mode": self.args.mode,
                  "networkScope": self.args.network_scope, "publicNetworkStatus": "NOT RUN", "independentNetworkStatus": "NOT RUN", "publicRelayStatus": "NOT RUN",
                  "scope": {"independent-public": "physical independent-public QUIC replication",
                            "shared-hotspot": "physical shared-hotspot LAN-only QUIC interoperability",
                            "shared-uplink-public-relay": "physical encrypted public-relay replication over a shared hotspot Internet uplink"}[self.args.network_scope] +
                           " with synthetic pre-authorized trust; not invitation UI",
                  "namespace": self.namespace, "macPrivateRoot": str(self.mac_root), "apkInstalledByDriver": False}
        handles = []
        try:
            result["networkBefore"] = self.preflight()
            self.choose_bind_addresses()
            result["androidPowerBefore"] = self.power_state("before-endpoints", require_ready=True)
            role = "initiator" if self.args.direction == "mac-to-android" else "acceptor"
            launch = {"role": role, "mode": self.args.mode, "deadlineSeconds": self.args.deadline_seconds}
            if self.args.network_scope == "shared-uplink-public-relay":
                launch["loopbackQuicForQA"] = True
            elif self.args.mac_bind:
                launch["bindAddress"] = self.args.mac_bind
            write_private(self.mac_root / "launch.json", encoded(launch))
            native_log = (self.output / "mac.log").open("wb"); handles.append(native_log)
            endpoints_started = time.monotonic()
            native = subprocess.Popen([str(Path(self.args.mac_executable).expanduser().resolve()), "--root", str(self.mac_root)],
                                      cwd=ROOT, stdout=native_log, stderr=subprocess.STDOUT, start_new_session=True)
            phone_log = (self.output / "android-instrumentation.log").open("wb"); handles.append(phone_log)
            args = ["shell", "am", "instrument", "-w", "-r", "-e", "class", TEST,
                    "-e", "physicalQa", "explicit-test-app-only", "-e", "expectedModel", self.model,
                    "-e", "qaRunId", self.run_id, "-e", "nativeP2pQa", "explicit-public-p2p-only",
                    "-e", "p2pNamespace", self.namespace, "-e", "p2pRole", "acceptor" if role == "initiator" else "initiator",
                    "-e", "p2pMode", self.args.mode, "-e", "p2pNetworkScope", self.args.network_scope,
                    "-e", "p2pDeadlineSeconds", str(self.args.deadline_seconds)]
            if self.args.android_bind:
                args += ["-e", "p2pBindAddress", self.args.android_bind]
            args += [RUNNER]
            logcat = (self.output / "together-logcat.txt").open("wb"); handles.append(logcat)
            logger = subprocess.Popen(self.adb + ["logcat", "--uid", self.uid, "-v", "threadtime", "-T", "1"],
                                      stdout=logcat, stderr=subprocess.STDOUT, start_new_session=True)
            instrument = subprocess.Popen(self.adb + args, stdout=phone_log, stderr=subprocess.STDOUT, start_new_session=True)
            copied = set()
            peer_descriptor = own_descriptor = phone_result = mac_result = None
            # APK/signature/network preflight is not part of either endpoint's
            # unchanged per-phase deadline. Total elapsed still includes it.
            deadline = endpoints_started + self.args.deadline_seconds + 30
            while time.monotonic() < deadline:
                self.stage("mac", self.local_json("stage.json"))
                self.stage("android", self.pull("stage.json"))
                phone_error = self.pull("error.json")
                mac_error = self.local_json("error.json")
                if phone_error or mac_error:
                    write_private(self.output / "endpoint-error.json", encoded({"mac": mac_error, "android": phone_error}))
                    raise GateError("A native endpoint failed; inspect endpoint-error.json")
                if "descriptor" not in copied:
                    value = self.pull("descriptor.json")
                    own = self.local_json("descriptor.json")
                    if value is not None and own is not None:
                        peer_descriptor, own_descriptor = descriptor(value), descriptor(own)
                        require(peer_descriptor["deviceId"] != own_descriptor["deviceId"] and peer_descriptor["userId"] != own_descriptor["userId"], "Independent partner device/user identities required")
                        write_private(self.mac_root / "peer-descriptor.json", encoded(peer_descriptor))
                        write_private(self.output / "android-descriptor.json", encoded(peer_descriptor))
                        write_private(self.output / "mac-descriptor.json", encoded(own_descriptor))
                        copied.add("descriptor")
                for name in ("genesis-body.json", "authorization.json"):
                    if name not in copied:
                        value = self.local_json(name)
                        if value is not None:
                            require((name == "genesis-body.json" and value.get("version") == 4 and len(value.get("roots", [])) == 2) or
                                    (name == "authorization.json" and set(value) == {"genesis", "events"} and value["events"] == []), "Public synthetic authorization shape mismatch")
                            self.push(name, encoded(value)); copied.add(name)
                if "signature" not in copied and peer_descriptor is not None:
                    value = self.pull("signature.json")
                    if value is not None:
                        require(set(value) == {"deviceId", "signature"} and value["deviceId"] == peer_descriptor["deviceId"] and valid_base64(value["signature"], 64), "Invalid public genesis co-signature")
                        write_private(self.mac_root / "peer-signature.json", encoded(value)); copied.add("signature")
                if "contacts" not in copied and peer_descriptor is not None:
                    phone_contact, mac_contact = self.pull("contact.json"), self.local_json("contact.json")
                    if phone_contact is not None and mac_contact is not None:
                        phone_contact = public_contact(phone_contact, peer_descriptor, self.args.mode)
                        mac_contact = public_contact(mac_contact, own_descriptor, self.args.mode)
                        if self.args.network_scope == "shared-uplink-public-relay":
                            for contact in (phone_contact, mac_contact):
                                require(contact["address"].get("relayURL"), "Shared-uplink public-relay scope needs both relay hints ready")
                                contact["address"]["directAddresses"] = []
                        require(phone_contact["binding"]["body"]["spaceId"] == mac_contact["binding"]["body"]["spaceId"] and phone_contact["binding"]["body"]["authorizationDigest"] == mac_contact["binding"]["body"]["authorizationDigest"], "Endpoint authorization archives differ")
                        self.route_hints(phone_contact, "mac-to-android")
                        self.route_hints(mac_contact, "android-to-mac")
                        write_private(self.mac_root / "peer-contact.json", encoded(phone_contact))
                        self.push("peer-contact.json", encoded(mac_contact)); copied.add("contacts")
                phone_result = self.pull("result.json")
                mac_result = self.local_json("result.json")
                if phone_result is not None or mac_result is not None:
                    if phone_result is not None:
                        write_private(self.output / "android-result.json", encoded(phone_result))
                    if mac_result is not None:
                        write_private(self.output / "mac-result.json", encoded(mac_result))
                    require(not phone_result or phone_result.get("status") == "PASS", "Android native endpoint reported failure")
                    require(not mac_result or mac_result.get("status") == "PASS", "Mac native endpoint reported failure")
                if phone_result is not None and mac_result is not None:
                    break
                require(native.poll() is None and instrument.poll() is None, "Endpoint exited before reciprocal verification")
                time.sleep(0.2)
            require(phone_result is not None and mac_result is not None, "Public P2P acceptance reached its bounded deadline")
            checkpoints = [item.get("checkpoint") for item in (phone_result, mac_result)]
            require(checkpoints[0] == checkpoints[1] and checkpoints[0].get("count") == 259 and
                    re.fullmatch(DIGEST_RE, checkpoints[0].get("digest", "")), "Exact 259-fact content/certificate checkpoints do not match")
            flags = ("partnerPersisted", "identityRetained", "reopenCheckpointRetained", "reopenedAcknowledgementRetained", "tombstoneRetained")
            for endpoint in (phone_result, mac_result):
                require(all(endpoint.get(flag) is True for flag in flags) and endpoint.get("operationCount") == 259,
                        "Persistence, identity, tombstone or signed partner-ACK check failed")
            selected = verified_selected_paths((phone_result, mac_result), direct_only=self.args.mode == "directOnly")
            if self.args.network_scope == "shared-uplink-public-relay":
                selected = verify_shared_uplink_relay_paths(mac_result, phone_result)
                result["connectivityPath"] = "encrypted-public-relay-shared-uplink"
            else:
                result["connectivityPath"] = ("direct-hotspot-LAN" if self.args.network_scope == "shared-hotspot" else
                    ("encrypted-relay-fallback" if any(path.get("relayed") for path in selected) else "direct-public-IP"))
            result["networkAfter"] = self.network_gate("after")
            def await_phone_completion():
                require(instrument.wait(timeout=20) == 0, "Android endpoint did not close cleanly")
                phone_log.flush()
                text = (self.output / "android-instrumentation.log").read_text(errors="replace")
                verify_instrumentation(text)
                restoration = self.pull("network-restoration.json")
                if restoration is not None:
                    write_private(self.output / "android-network-restoration.json", encoded(restoration))
                result["androidNetworkRestoration"] = verify_network_restoration(restoration)

            def await_mac_completion():
                require(native.wait(timeout=20) == 0, "Mac endpoint did not close cleanly")

            finish_participant_barrier(
                finish_phone=lambda: self.push("finish", b""),
                await_verified_phone=await_phone_completion,
                finish_mac=lambda: write_private(self.mac_root / "finish", b""),
                await_mac=await_mac_completion)
            require(mac_result.get("processPid") == native.pid, "Initial Mac process ID does not match the owned QA CLI")

            # The first networking processes have exited. This launches wholly
            # fresh processes against the same isolated stores; no new identity,
            # socket, fixture or operation may be generated by either verifier.
            mac_reopen_log = (self.output / "mac-reopen.log").open("wb"); handles.append(mac_reopen_log)
            reopen_native = subprocess.Popen([str(Path(self.args.mac_executable).expanduser().resolve()), "--reopen-root", str(self.mac_root)],
                                             cwd=ROOT, stdout=mac_reopen_log, stderr=subprocess.STDOUT, start_new_session=True)
            require(reopen_native.wait(timeout=30) == 0, "Mac fresh-process reopen failed")
            mac_reopen = self.local_json("reopen-result.json")
            require(mac_reopen is not None and mac_reopen.get("processPid") == reopen_native.pid,
                    "Mac fresh-process result is missing or does not belong to the owned verifier")
            write_private(self.output / "mac-reopen-result.json", encoded(mac_reopen))
            mac_restart = verify_fresh_process_reopen(mac_result, mac_reopen, checkpoints[0])

            phone_reopen_log = (self.output / "android-reopen-instrumentation.log").open("wb"); handles.append(phone_reopen_log)
            reopen_args = list(args)
            reopen_args[reopen_args.index(TEST)] = REOPEN_TEST
            reopen_args[reopen_args.index("p2pDeadlineSeconds") + 1] = "60"
            reopen_instrument = subprocess.Popen(self.adb + reopen_args, stdout=phone_reopen_log,
                                                 stderr=subprocess.STDOUT, start_new_session=True)
            require(reopen_instrument.wait(timeout=65) == 0, "Android fresh-process reopen failed or reached its deadline")
            phone_reopen_log.flush()
            verify_instrumentation((self.output / "android-reopen-instrumentation.log").read_text(errors="replace"))
            phone_reopen = self.pull("reopen-result.json")
            require(phone_reopen is not None, "Android fresh-process result is missing")
            write_private(self.output / "android-reopen-result.json", encoded(phone_reopen))
            phone_restart = verify_fresh_process_reopen(phone_result, phone_reopen, checkpoints[0])
            result["freshProcessReopen"] = {"mac": mac_restart, "android": phone_restart, "status": "PASS"}
            result["networkAfterReopen"] = self.network_gate("after-reopen")
            result.update(status="PASS", checkpoint=checkpoints[0], durablePartnerAck=True,
                          reopenedIdentityAndAck=True, tombstoneRetained=True,
                          publicNetworkStatus="PASS" if self.args.network_scope == "independent-public" else "NOT RUN",
                          independentNetworkStatus="PASS" if self.args.network_scope == "independent-public" else "NOT RUN",
                          publicRelayStatus="PASS" if self.args.network_scope == "shared-uplink-public-relay" else "NOT RUN",
                          passed=2, failed=0, skipped=0)
        except Exception as error:
            # Exception strings may contain paths/IPs from libraries; private only.
            write_private(self.output / "driver-error.json", encoded({"type": type(error).__name__, "message": str(error)}))
            result["error"] = "Acceptance failed; inspect private driver-error.json and stage logs"
        finally:
            # A host adb subprocess disappearing does not necessarily stop its
            # phone-side instrumentation. Request cancellation only in this
            # driver's freshly generated namespace, leaving Android's finally
            # block a bounded chance to close native endpoints and restore its
            # optional process-only Network binding. Never force-stop any app.
            cleanup = {"abortRequested": False, "instrumentStillRunning": False}
            active_instrument = next((child for child in (reopen_instrument, instrument)
                                      if child is not None and child.poll() is None), None)
            if result["status"] != "PASS" and active_instrument is not None:
                cleanup_started = time.monotonic()
                try:
                    self.push("abort", b"", command_timeout=3)
                    cleanup["abortRequested"] = True
                    try:
                        cleanup["instrumentReturnCode"] = active_instrument.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        cleanup["instrumentStillRunning"] = True
                except Exception as error:
                    cleanup["abortErrorType"] = type(error).__name__
                    cleanup["instrumentStillRunning"] = active_instrument.poll() is None
                cleanup["elapsedSeconds"] = round(time.monotonic() - cleanup_started, 3)
            if instrument is not None:
                try:
                    restoration = self.pull("network-restoration.json")
                    if restoration is not None:
                        write_private(self.output / "android-network-restoration.json", encoded(restoration))
                    cleanup["networkRestoration"] = verify_network_restoration(restoration)
                except Exception as error:
                    cleanup["networkRestoration"] = {"status": "NOT VERIFIED", "errorType": type(error).__name__}
                    if result["status"] == "PASS":
                        result["status"] = "FAIL"
                        result["error"] = "Android process Network restoration could not be verified; inspect cleanup.json"
                        for status in ("publicNetworkStatus", "independentNetworkStatus", "publicRelayStatus"):
                            if result.get(status) == "PASS":
                                result[status] = "FAIL"
            write_private(self.output / "cleanup.json", encoded(cleanup))
            if getattr(self, "model", None):
                try:
                    result["androidPowerAfter"] = self.power_state("after-endpoints", require_ready=False)
                except Exception as error:
                    result["androidPowerAfter"] = {"status": "UNKNOWN", "errorType": type(error).__name__, "networkFailureCause": "UNKNOWN"}
            for child in (native, instrument, reopen_native, reopen_instrument, logger):
                stop_owned(child)
            for stream in handles:
                stream.close()
            if "networkBefore" in result and "networkAfter" not in result:
                try:
                    result["networkAfter"] = self.network_gate("after")
                except Exception as error:
                    write_private(self.output / "network-after-error.json", encoded({"type": type(error).__name__, "message": str(error)}))
                    result["networkAfter"] = {"status": "FAIL", "reason": "Post-run network condition could not be verified"}
                    result["status"] = "FAIL"
            result["elapsedSeconds"] = round(time.monotonic() - self.started, 3)
            result["copiedPublicStages"] = sorted(locals().get("copied", set()))
            write_private(self.output / "summary.json", encoded(result))
            print(json.dumps({key: result[key] for key in ("status", "direction", "mode", "networkScope", "publicNetworkStatus", "elapsedSeconds")}), flush=True)
        return 0 if result["status"] == "PASS" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--mac-executable", default=str(ROOT / "packages/together-p2p-swift/.build/debug/TogetherP2PPublicQA"))
    parser.add_argument("--output", default=str(ROOT / "qa/results" / ("p2p-public-" + time.strftime("%Y%m%d-%H%M%S"))))
    parser.add_argument("--mode", choices=("directOnly", "automatic"), default="directOnly")
    parser.add_argument("--network-scope", choices=("independent-public", "shared-hotspot", "shared-uplink-public-relay"), default="independent-public",
                        help="Explicit hotspot LAN or public-relay/shared-uplink tests never count as independent-network acceptance")
    parser.add_argument("--direction", choices=("mac-to-android", "android-to-mac"), required=True)
    parser.add_argument("--mac-bind")
    parser.add_argument("--android-bind")
    parser.add_argument("--deadline-seconds", type=int, default=180)
    args = parser.parse_args()
    require(30 <= args.deadline_seconds <= 300, "Endpoint deadline must be 30–300 seconds")
    require(args.network_scope != "shared-hotspot" or args.mode == "directOnly", "Shared-hotspot scope is direct-only LAN interoperability")
    require(args.network_scope != "shared-uplink-public-relay" or (args.mode == "automatic" and args.mac_bind is None),
            "Shared-uplink public relay needs automatic mode and the QA loopback-only Mac QUIC preset")
    executable = Path(args.mac_executable).expanduser().resolve()
    expected = ROOT / "packages/together-p2p-swift/.build"
    require(executable.is_relative_to(expected.resolve()) and executable.name == "TogetherP2PPublicQA" and executable.is_file() and os.access(executable, os.X_OK),
            "Only the built isolated TogetherP2PPublicQA CLI is allowed; never launch the production App")
    for bind in (args.mac_bind, args.android_bind):
        if bind is not None:
            require(public_socket(bind, allow_zero=True), "Explicit bind address must be a global IP socket (port 0 requests an ephemeral port)")
    prior = os.umask(0o077)
    try:
        return PhysicalP2P(args).run()
    finally:
        os.umask(prior)


if __name__ == "__main__":
    raise SystemExit(main())
