# Public Mac–Samsung P2P acceptance — 2026-10-19

## Status

**BLOCKED: ADB stopped listing the authorized Samsung before public payload
exchange. The connection-loss cause is UNKNOWN. No public no-VPN direction has
passed.** The current installed Mac
Build 13 and Android code 8 still use C1; the test transport does not replace
either installed application. No production Worker, pairing or user store changed.

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

## Verified so far

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

## Reproduce after USB reconnection

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
