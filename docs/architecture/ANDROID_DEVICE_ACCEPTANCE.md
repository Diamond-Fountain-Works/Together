# Android Phase C: acceptance boundary and test isolation

Baseline: Phase B `7e9d0c1182ff2741af748e0f976509058039d2c4`, still-open Draft PR #6.
Independent worktree/branch `android-physical-phase-c` / `feature/android-physical-phase-c`.
The network envelope remains Protocol4 / Relay API2, Room1. No business model, signer encoding,
root/device identity, merge rule, production transport or deployment is replaced by this phase.

## Physical host

The checksum-pinned Phase B APK is installed first in `com.together.android.debug`, after live ADB
authorization/model/ABI and absent-package checks. Subsequent changes use same-certificate `install -r`
only. The host driver checks both APK application IDs, Debug flag and the known Debug certificate;
it refuses a different signer rather than uninstalling. It never calls `pm clear` or Gradle connected
tests on hardware, because Gradle may uninstall the target/test APK at the end.

`IsolatedAndroidTestRunner` keeps the emulator default but requires a model-bound physical opt-in,
run UUID and explicit loopback URL on hardware. Tests create separate Room names, `qa-<UUID>`
no-backup roots and independent Keystore slots. Foundation UI also uses an explicit namespace,
so it cannot silently select the normal Debug workspace. A passive test-only listener captures
thread stacks if Runner teardown fails to terminate. Native OS permissions are handled by the user;
physical tests never click a permission dialog or grant the microphone in code.

The Debug-only `BusinessQaActivity` can reopen an existing enrolled synthetic namespace. External
physical launch additionally requires an expiring token bound to that exact namespace. The permit
is local test machinery, not a pairing credential or production feature. Production builds contain
neither this Activity nor test fixtures. The host holds its own screen awake only while visible and
exposes existing Compose test tags to native UI automation. No system keyboard/radio setting changes.

## Real native/phone integration

`test_android_physical_bridge.py` launches an explicitly opted-in Swift Testing QA process with a
fresh guarded temporary root. It never launches Together.app, reads production defaults or chooses
a default database/identity path. Two native roots establish a synthetic V3 legacy pair and explicitly
migrate its unchanged space/history to V4. Android independently generates its key in a separate
Keystore slot, imports a signed public offer, proves possession, and receives the root's signed
completion. No private key is copied between processes/devices.

Only public signed enrollment DTOs, generated PNG/WAV and diagnostic summaries pass through ADB.
Business and media transfer itself goes through actual authenticated encrypted C1 WebSockets and
the existing 64KiB resource channel. The driver uses a dedicated USB reverse to a local Worker with
private state. This is physical phone/native Swift interoperability, **not public cross-WiFi** and
not a claim of graphical Mac enrollment-panel acceptance.

The round verifies legacy task/tombstone history, both directions, wish request/confirmation,
CNY/AA/reserves, a single bill instance, media hashes and separate content receipts, concurrent
offline field edits, full inventory equality, per-device signed ACK restoration, repeated operation
idempotence, actual Android force-stop/new-process recovery and fresh-ticket refusal after revocation.

## Reliability and performance

`PhysicalReliabilityTest` closes only owned test sockets, injects an unavailable link, overlaps
cancel/new-run and duplicate connect requests, and catches up 1,025 facts across real Room-backed
clients through the Worker. A separate in-process frame pump on physical Room deliberately drops
ACKs and verifies no false persisted state, then reconnects and repeats receipts. It does not claim
that TCP drops individual frames without a disconnect. The three clients converge before that final
two-client ACK subcase; its extra fact intentionally remains absent from the stopped third client.

The original Phase B native reconnect timeout is retained, not renamed as a fixed runtime defect.
Successful reproducer repetitions/fault cases cannot prove its root cause. Tests add stage/state/error
diagnostics without global timeout increases or removing convergence assertions.

The explicit 100k workload uses 100,000 real device-signed/certified facts, Room transactions,
bounded 128-entry pages, a content digest, pinned inventory and full restart verification. It measures
the physical phone's timings/PSS/heap and optional scoped Simpleperf samples. Full 100k UI projection
or public-network transfer is a separate claim and is not inferred. Additional workloads cover large
original media and a 3,000-fact finance projection/review page. Debug/OEM/JIT/thermal variation is recorded;
Mac benchmark numbers do not stand in for Android measurements.

## Remaining gates

[Phase C QA](../qa/reports/ANDROID_PHASE_C.md) is the outcome authority. Physical screenshots stay
local candidates; no approved baseline is replaced. [Staging plan](../qa/ANDROID_STAGING_ACCEPTANCE.md)
requires separate account/deployment approval and separate DO namespaces, never production reuse.
Public-network/carrier/four-device/minimum-API/TalkBack and independent cryptographic review remain
distinct gates. APKs, private stores, original media, scoped Logcat and profiles never enter Public GitHub.
