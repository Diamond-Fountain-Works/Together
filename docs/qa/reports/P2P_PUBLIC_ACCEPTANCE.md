# Public Mac–Samsung P2P acceptance — 2026-10-20

## Status

**BLOCKED: the authorized Samsung is connected again, but currently locked;
the Mac uses that same Samsung's hotspot. Independent-network public acceptance
has not passed.** The current installed Mac
Build 13 and Android code 8 still use C1; the test transport does not replace
either installed application. No production Worker, pairing or user store changed.

## October 20 debugging and retained results

- Fresh owner-only backup outside the repository: Android private test archive,
  previous test APK and a four-file Mac production identity/database manifest.
  All four Mac hashes still match after the attempts. Only the instrumentation
  APK was updated, after checking its existing signer; the host App was retained.
- Two early preflight failures exposed an overly broad Wi-Fi detector. An enabled
  radio is not an Internet route, and Samsung's `LOCAL_NETWORK` hotspot is not
  Internet Wi-Fi. The guard now examines network capabilities and source routes.
  It still rejects active VPNs, Internet Wi-Fi on the phone and unknown routes.
- Mac global IPv6 belongs to the phone hotspot's prefix, and its default gateway
  matches the phone AP. This is **shared-hotspot LAN**, not two independent public
  networks. ICMPv6 to the phone AP passed 2/2; that does not prove QUIC delivery.
- First explicit shared-hotspot native attempt: **FAIL**, 45.169 seconds,
  Mac native connect timed out. Phone last stage was contact publication; logs
  do not prove it entered `accept`. Cause **UNKNOWN**. The old instrumentation
  outlived its deadline; its scoped log was retained and only its verified owned
  PID was terminated. No data clear/uninstall was used.
- New test-only handling selects the exact local AP network for the LAN case,
  restores the previous process binding in `finally`, adds granular contact
  stages and an owned-namespace abort control. Successful instrumentation exit
  and a post-cleanup restoration witness are mandatory. These runtime paths are
  **NOT RUN** until an unlocked-phone retry; coroutine timeouts alone are not
  claimed to bound a blocking native destructor.
- Latest retry correctly stopped in preflight in 9.662 seconds: phone was
  `Dozing`, keyguard showing. No endpoint was launched. User unlock is required;
  the driver never wakes/unlocks the phone or edits lock-screen settings. Whether
  Doze contributed to the earlier native failure remains **UNKNOWN**.
- Completion barrier corrected: request phone finish, verify its actual JUnit
  exit and network restoration, then finish Mac. A premature socket close or
  already-written result can no longer substitute for successful process exit.
- Swift's pinned native `online()` future does not provide a reliable cancellable
  wait. QA now polls only for a relay address with a bounded cancellable wait;
  this is a routing hint, never a claim that relay connection succeeded.

Local regression: **42 PASS / 0 FAIL / 0 SKIP** (32 driver, 3 core binding,
4 optional native QUIC, 3 actual CLI root guards). Portable protocol checks:
**25 PASS / 0 FAIL** (17 Python, 8 Swift). Android JVM:
**53 PASS / 0 FAIL / 3 SKIP**; app JVM target has no tests. Strict Android test-APK
build and Swift QA build pass. `make protocol-test` initially lacked this
worktree's optional Python environment; its exact Python/Swift suites subsequently
passed using the existing pinned QA runtime. Android JVM startup initially lacked
`ANDROID_HOME`; rerun with the existing SDK passed. These setup errors are retained.

Publication gate: tracked source plus reachable history **PASS**, 538 files /
941 historical blobs, zero findings. Android Copy QA **PASS** (578 entries,
zero warnings); Apple Copy QA **WARN**, zero errors / 14 existing warnings.
Visual QA **NOT RUN**; no product UI or approved baseline changed. PR #10 stays
Draft. Before this update, three prior-head CI jobs passed and two arm64 jobs
were cancelled because a hosted runner was not acquired; cancellation is not a
test PASS. Latest-head CI must be reported separately after publication.

Physical public direct, public encrypted relay, reverse direction, complete
259-operation/ACK/restart acceptance and media are **NOT RUN / BLOCKED**; no
partial network observation is reported as a replication PASS. Current test-only
APK SHA-256: `a57d16ef5ec54970ffa4e899a05e0d0424bc8a68fc7280a78e1cf52a263304a1`.
All actual topology, addresses, serial, logs and synthetic private stores remain
in ignored local `qa/results/p2p-public-20261020/` and private backups.

## Explicit network scopes

- Default `independent-public`: must prove independent Mac Wi-Fi and phone mobile
  routes; rejects the currently shared hotspot topology.
- `shared-hotspot` + `directOnly`: local interoperability only. Public acceptance
  remains **NOT RUN**, even if every operation assertion passes.
- `shared-uplink-public-relay` + `automatic`: a separate proposed runtime check.
  Mac application QUIC sockets are constrained to both loopback families using
  the pinned public preset API, verified before/after connection. Both endpoints
  must report selected relay paths and check every completed application frame.
  Contacts carry relay hints only; phone retains its mobile default. This can
  verify actual encrypted public relay access without VPN, but still cannot
  prove independent-network NAT traversal. Other UDP helper traffic is outside
  the loopback application-socket assertion. Runtime result **NOT RUN**.

## October 19 historical failure

ADB stopped listing the authorized Samsung before public payload exchange. The
connection-loss cause remains **UNKNOWN**; reconnection does not resolve it.

The first Mac-to-Android attempt stopped during test initialization. A bounded
temporary-root check rejected macOS Foundation's `/tmp` canonicalization of the
same directory Python exposes as `/private/tmp`. The failure was reproduced and
the guard now accepts both aliases of that system-temporary parent, while still
requiring the QA-only directory prefix. A smoke run subsequently generated an
independent test identity in the allowed directory; missing arguments and the
production Application Support path still fail closed. This is a harness fix,
not evidence of a network failure or a successful connection.

The phone started the isolated instrumentation and published its synthetic
descriptor. It was no longer listed by ADB shortly afterward. Original attempt logs
and network evidence remain in ignored `qa/results/p2p-public-*` directories. No
operation payload traversed that first attempt. Public direct connection,
automatic relay fallback, both invitation directions and physical media remain
**NOT RUN**. Reconnect the authorized USB device to resume.

## Implemented acceptance tools

- Optional native `TogetherP2PPublicQA --root <private-temporary-directory>`.
  It cannot open the default application store. Persistent QA identities and
  independent transport keys remain owner-only in the isolated directory.
- Android **test target only**: native Iroh 1.1.0, exact endpoint binding/ALPN,
  bounded stream frames and the existing Protocol 4 cipher/Room/AntiEntropy.
  Strict dependency verification remains enabled; published Maven artifacts
  were compared to downloaded bytes. This is not an independent protocol audit.
- `scripts/test_p2p_physical.py`: authorized physical Samsung/model/Debug signer,
  Mac Wi-Fi routes, Samsung validated mobile/no VPN, proxy absence and no ADB
  reverse are checked before and after every run. Global address hints and
  transport path classification stay in local-only evidence.
- USB carries allowlisted **public trust/contact material and diagnostics**.
  Signed operation records, databases, signing seeds and original media are not
  copied through that bootstrap channel. This verifies pre-authorized synthetic
  partner roots; it does **not** verify the product invitation-code UI.
- Each direction must exchange 129 independent facts per device across an
  inventory page boundary, then the phone's tombstone as fact 259. Exact
  content/certificate checkpoints, signatures, projections and genuine remote
  persistence receipts must agree. Sending a frame is never an ACK.
- Both participants must then exit. Separate Mac and Android processes reopen
  the same isolated stores, require different PIDs and verify existing identity,
  checkpoint, tombstone and signed receipt membership without networking.

## October 19 verification (historical counts)

- Swift QA executable: **BUILD PASS**. It is not the production Mac App.
- Android instrumentation: **BUILD PASS**, with strict Gradle verification.
  Only the test APK was installed after matching the existing Debug signer;
  the host App was not reinstalled or cleared. A later test-only rebuild is
  waiting for USB reconnection before installation.
- Network-gate/signer/recovery/Runner pure tests: **11 PASS / 0 FAIL**.
- Actual Mac QA root/identity guards: **3 PASS / 0 FAIL**; both temporary aliases
  work and missing restart state cannot create a replacement identity/store.
- Existing native local P2P tests: **5 PASS / 0 FAIL**, including the three core
  trust tests. These are local tests, not physical public network results.
- Initial read-only observations: Mac default IPv4/IPv6 routes used Wi-Fi;
  Samsung used validated mobile data without an active VPN; proxies/ADB reverse
  were absent. These point-in-time observations do not prove subsequent traffic.
- Safety: an owner-only pre-test archive and production-file manifest were saved
  outside the repository. No app uninstall, data clear, key migration, production
  install, network setting change, Cloudflare deployment or PR merge occurred.

## Reproduce after manual unlock and topology confirmation

Build the optional Swift CLI and Android instrumentation, verify the installed
Debug signer, and install **only** the test APK with `adb install -r`. Keep the
same host App and data. With the phone using mobile data and Mac using Wi-Fi:

```sh
python3 scripts/test_p2p_physical.py --serial <authorized-serial> \
  --direction mac-to-android --mode directOnly \
  --output qa/results/p2p-public-<run>/mac-to-android
python3 scripts/test_p2p_physical.py --serial <authorized-serial> \
  --direction android-to-mac --mode directOnly \
  --output qa/results/p2p-public-<run>/android-to-mac
```

The driver bounds owned processes and refuses existing evidence directories.
It never installs software or modifies network settings. A missing global IPv6
route, unknown signer, active VPN/proxy or USB network route fails the gate.
Automatic Iroh helper/relay mode must be recorded as a **separate** attempt;
a selected relay path cannot be called a direct-P2P result. No new helper or
production service is deployed by this driver.

The current driver also requires verified global IPv6 in automatic mode. It
does not yet cover IPv4-only NAT/relay fallback; that limitation is a test-harness
gate, not a claim that every future P2P deployment must require IPv6.

Production invitation/contact UX, Android app integration, reconnect/offline
mutation, media transfer, public NAT diversity, platform support and independent
security review remain separate release gates. Current QA screenshots and
previously deferred visual reviews retain their existing approval state.
