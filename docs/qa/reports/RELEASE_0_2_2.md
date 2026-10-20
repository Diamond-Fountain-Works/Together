# Together 0.2.2 delivery gate

This report separates a normal, installable local-test artifact from a generally
accepted stable release. Source baseline: `94fb9cb7222e1434fba8724241601f9246ab5c14`.
The release branch promotes the existing native partner adapter; it does not add
a new ledger, signed-operation format, sync engine or production service.
The initial normal artifacts were Mac Build 19 and Android versionCode 13. They
were not accepted for delivery after the upstream native dependency advisories
below were verified. The tested replacement checkpoints are Mac Build 20 and
Android versionCode 15; Android code 14 was subsequently rejected for the runtime
failure below. Metadata alone never proves that a packaged or installed binary
passed acceptance. The hashes in this report identify tested checkpoints, not a
promise that a later commit-stamped delivery package has identical bytes. Final
delivery hashes belong in the release manifest after that package is inspected.

## Evidence carried forward

[Native app acceptance](NATIVE_APP_NETWORK_ACCEPTANCE.md) records actual isolated
Mac and Samsung UI tests, not just CLI fixtures:

- Samsung invitation, explicit identity comparison and mutual confirmation.
- Task persistence on the peer, signed durable ACK, offline edits, field merge,
  and Android force-stop/restart with the same identity and history.
- Actual synthetic financial records: deposit 20.00, shared expense 3.01,
  resulting reserves 16.99; a separate AA expense 3.01 preserves reserves and
  allocates 1.50 / 1.51 deterministically.
- Wish grant 2, fulfilment request and beneficiary confirmation: fulfilled 1,
  remaining 1.
- Original photo and reverse-direction audio transfer, exact SHA-256, verified
  photo export, manually played audio, sealed startup reveal and one-time state.
- Final read-only comparison: 21 signed operations, including 14 Protocol 4
  envelopes and 7 preserved pre-activation facts, equal on both devices.

The Mac VPN was active. The phone used its independent cellular connection with
no VPN. An encrypted relay was used; this is **not** proof of VPN-free direct P2P
or acceptance of both devices without VPN. CLI/local tests are separate evidence.

## New normal-release checks

| Gate | Status | Required evidence |
| --- | --- | --- |
| Normal Mac bundle/version/native linkage | PASS | Actual fixed-dependency Build 20 artifact; static FFI symbols verified |
| Normal Android package/version/native linkage | PASS | Actual signed code 15 checkpoint, including shipped DEX JNI ABI checks |
| Release signatures, entitlements and debugger flags | PASS | Both tested artifacts passed; Mac ad-hoc/notarized-distribution limitations retained |
| Native-library 16KiB ELF and APK ZIP alignment | PASS | Tested arm64 APK: all LOAD segments and ZIP alignment checked separately |
| Package excludes user stores and keys | PARTIAL | Both tested artifact private-path checks passed; full publication gate is separate |
| Normal Mac first launch and restart | PASS | Authorized installed Build 20: empty setup, no role preselection, same identity after restart |
| Normal Android native startup/invitation/cancel | PASS | Installed code 15 on emulator; real normal-App UI, same live process through cancellation |
| Normal Android physical first launch and restart | NOT RUN | Samsung not connected for this release checkpoint |
| Normal-App two-way invitation/authentication | NOT RUN | Both normal Apps, independently verified device identities |
| Normal-App task, durable ACK and offline catch-up | NOT RUN | Actual peer persistence and signed acknowledgement |
| Both endpoints without VPN | NOT RUN | Network state and actual selected path at test time |
| Normal-App finances, wishes and original media | NOT RUN | Actual UI operations and exact persisted results/hashes |
| Independent protocol/security review | BLOCKED | Developer regression tests do not substitute for independent review |
| Known upstream Iroh availability advisories | PARTIAL | Both rebuilt native inputs verify the fixed lock; App interoperability validation and original upstream test proof gaps remain |
| Human visual baseline approval | REVIEW REQUIRED | Existing candidates stay candidates |

Use `python3 scripts/test_release_delivery.py --mac-app <bundle> --android-apk
<apk> --json qa/results/release-0.2.2/artifacts.json` for read-only metadata,
signature, entitlement, native-library alignment and packaged-private-file
inspection. It never builds, launches, signs, installs, resets or deploys. An
artifact PASS does not pass the network, migration, UI or security gates above.

### Withdrawn Build 19 artifact

Actual read-only inspection of `Together.app` passed normal bundle identity,
0.2.2 Build 19, arm64/macOS 14.5, signature verification, required entitlements,
disabled debugger access and packaged private-file exclusions. Native Iroh is
statically linked in the executable: `nm` found 53 defined FFI and 360 UniFFI
symbols, rather than relying on a filename, Info.plist label or embedded string.

- Executable SHA-256:
  `d7074840a56becde583751084f34bc56f8241be240863c9a5d97263e05164976`.
- DMG: `Together-0.2.2-Build19-AppleSilicon.dmg`, 10,393,088 bytes.
- DMG SHA-256:
  `7497ae0d7e5f1bfd28408e9b929f19786f2b9de6452cc272ef22769433e20063`.
- Existing packaging report verifies 14 bundle entries, mounted bundle hashes,
  DMG checksum, metadata, signature and installation guide/shortcut.

This earlier Build 19 is retained as evidence, not the final delivery candidate.
The package is ad-hoc signed, not notarized, and Gatekeeper assessment rejects
it. The user accepted that local delivery limitation. This is not Developer ID
distribution, Intel support, or proof of installed-App/network acceptance.

### Frozen fixed-dependency Mac artifact

Final `Together.app` 0.2.2 Build 20 passed actual bundle, signature, entitlement,
disabled-debugger, private-path and static native-symbol checks. It is arm64 for
macOS 14.5+. Its executable SHA-256 is
`0d9d403281a350d55cc0cd056555cf2437ada83d7d868ce57870333e3929df4f`.
The final DMG, `Together-0.2.2-Build20-AppleSilicon.dmg`, is 10,517,504 bytes;
SHA-256:
`7df3ac21a9eb2cdea17cca9e0daf9395eb45989f3e83fbe2f0cfb936e8078f34`.
Its packaging report verifies the 14 mounted bundle entries and DMG checksum.

Independent read-only `rebuild_apple_native.py --verify-only` passed the local
fixed-source package receipt, exact lock/manifest and binding hashes, static
library layout, native exports and complete generated-package file hashes.
The fixed-source lock and manifest hashes remained unchanged after both platform
builds. This is source/ABI/artifact evidence, not independent security review.
The Mac artifact remains ad-hoc signed, unnotarized and rejected by Gatekeeper;
the accepted local-delivery limitation has not been hidden.

Root execution then installed this exact bundle after the separately authorized
backup/reset. Normal launch showed Welcome; the role step had no preselection
and disabled Continue until a choice. Back navigation, quit and relaunch worked.
There was one identity key with unchanged bytes after relaunch, one local profile
and zero task, wish, finance or gift entities. No QA fixture was imported and no
invented profile was entered. Setup was left for the user. This is a normal-App
startup/restart check, not a production-identity network or migration test.

### Pre-repair Android checkpoint

The frozen provisional Android APK was inspected before the native link repair.
Its SHA-256 was
`ad5bf9b7abf795ea10c8428e3a69605983ed1f90ad0bc29b50bd5f4708892b84`.
Actual package identity, 0.2.2/code 13, non-debuggable status, signature, arm64
contents and APK ZIP 16KiB alignment passed. No packaged private-file paths were
found. Its four Iroh LOAD segments remained 4KiB-aligned, so the artifact gate
correctly failed. Other packaged native libraries passed: JNA 64KiB and AndroidX
graphics 16KiB. This provisional APK is not the delivery artifact.

Android JUnit XML from this worktree records 66 passed, 0 failures/errors and 3
skipped: Protocol 19/0/2, Domain 38/0/1, App Release policy tests 9/0/0. The two
App suites cover namespace/identity fail-closed and profile setup rules. These
are JVM tests; they do not replace installed-App/Room/Keystore or physical
network acceptance. Full logs and artifact details remain in ignored results.

### Withdrawn code 14 and the JNA runtime regression

`Together-0.2.2-14-arm64.apk` passed the original read-only package inspection:
`com.together.android`, 0.2.2/code 14, signed, non-debuggable, not test-only,
arm64-only, no packaged private-file paths, all native LOAD alignment/congruence
checks and independent APK ZIP 16KiB alignment. It is 22,854,784 bytes; SHA-256:
`50900849e72332062e1b11abf0c967f5fa2d1449cf7ef669d302690aa5944952`.

The actual APK Iroh library bytes match the rebuilt AAR and its receipt:
`2168255f0beea7cf7ee57b1e8b6178a7f24738ee271b93ff9b2c4cc9f996749a`.
The AAR SHA-256 is
`673fc7a35c8ae23ab89d29d7bab7b0b220775f7addd620570da742e82bbd95c5`.
Five byte/hash checks link that APK library to the AAR, unchanged classes.jar,
receipt and tracked fixed lock/manifest. The rebuilt AAR preserves all 414
FFI/UniFFI/JNI exported names. This confirms build provenance and packaging;
native initialization, emulator/physical UI, no-VPN sync and restart acceptance
remain separate checks.

The real emulator UI exposed a failure that package metadata and ELF alignment
could not detect. Create Invitation crashed in JNA `Native.initIDs`: R8 renamed
the JNI-addressed `Pointer.peer` field to `d` and renamed `Structure`. The original
crash log and rejected code 14 APK remain local evidence. Code 14 is **FAIL and
withdrawn**, despite its earlier package checks passing.

The correction preserves JNA's JNI-facing dependency classes and members while
retaining application R8 optimization. The artifact checker now reads the actual
shipped DEX, requiring `Pointer.peer`, `Structure.memory`, `Structure.typeInfo`,
`IntegerType.value`, `PointerType.pointer` and native `Native.initIDs` with their
exact JNI types. It rejects code 14 and passes code 15. This check supplements,
and does not replace, actual native initialization.

### Tested code 15 Android checkpoint

`Together-0.2.2-15-arm64.apk` passed combined read-only inspection with Mac Build
20: normal package/version, non-debuggable/non-test-only flags, signature,
packaged-private-path exclusions, arm64 native libraries, all ELF LOAD
alignment/congruence checks, independent APK ZIP 16KiB alignment and all six
shipped DEX JNI checks. The tested checkpoint is 22,920,320 bytes; SHA-256:
`dfeb9ddd7a8d82f52f189253b3db0da50bae2a21f0839095c0888ac60c8b8eeb`.

Root execution upgraded the emulator with installation-in-place, preserving its
synthetic test profile. Normal App cold launch completed; Create Invitation
displayed the signed invitation and waiting state. Cancel returned to Local Only
and removed the invitation without a crash or process restart. The measured
1,287 ms cold launch is one emulator sample, **not Samsung performance**. Empty
Plans showed only Pending/Completed with no tasks; Wishes showed no grants and
the pairing guidance; all three Finances tabs showed zero real test records.
These are native-startup and usable-empty-state checks, not two-device pairing,
no-VPN network acceptance, or complete business UI acceptance.

A subsequent force-stop/relaunch and newly generated invitation retained the
same device ID, user ID and native endpoint public key. Cancel again returned
to Local Only. Expenses and Bills were separately opened: zero expenses and no
recurring bills were present. These checks use the disposable Android emulator,
not the disconnected Samsung or any partner's personal records.

## Platform and lifecycle boundaries

- The pinned Swift native dependency supports Apple Silicon and macOS 14.5+.
  An arm64 artifact must not be labelled Universal or Intel-compatible.
- The Samsung evidence covers its actual 4KiB-page device. It does not prove
  16KiB-device compatibility. Repacking or ZIP alignment cannot repair an ELF
  LOAD segment; a same-source rebuild needs locked dependencies and native
  compatibility tests.
- Native partner routing currently connects the two pinned partner devices.
  Existing C1 device-enrollment/revocation controls must not advertise native
  multi-device management until supported by that adapter.
- Existing C1 binding, stable user/device IDs, space, keys and historical signed
  facts must not be silently replaced. Fresh native pairing is distinct from
  migration of an existing C1 pairing. The Mac normal factory preserves its
  existing C1 route when a C1 binding exists. Android native Release currently
  refuses an existing C1 authorization without a native binding; it does not
  erase the store or silently authorize another device. This is an explicit
  upgrade limitation, not a passing migration test.
- Native endpoints use upstream discovery/relay helpers when direct traversal
  needs them. They do not use the Cloudflare business relay for native packets.
  A discovered relay URL is not proof of reachable service or authenticated sync.
- The 8-hour signed invitation is checked for fresh joins. Persisted authorized
  peers use signature/pin verification plus fresh Protocol 4 session binding;
  an expired invitation does not revoke a paired peer.
- Current normal Mac and Android native factories call this same signed-contact
  implementation. `versions.json` separately records native eight-hour JSON
  invitations (issuer/receiver local clocks), C1 v2 eight-hour codes (server
  clock/atomic consumption), and legacy C1 v1 ten-minute codes. The full existing
  conformance suite passed 18 tests after adding this distinction and checking
  the shared signed-contact fixture. The legacy Protocol 3 fixture is preserved;
  neither the server nor its deployed configuration changed in this audit.
- Local save, signed operation ACK and complete verified gift receipt remain
  separate. Socket send, relay forwarding and operation convergence cannot be
  described as complete media delivery.
- Android foreground/restart catch-up is supported by the existing adapter;
  permanent background connectivity and an offline server mailbox are not.

### Pinned Android native link repair

The [upstream issue](https://github.com/n0-computer/iroh-ffi/issues/285) and
[exact upstream fix](https://github.com/n0-computer/iroh-ffi/commit/c948937663ffe58df1a0a1bfda2def64e5bcdaa4)
identify 16KiB LOAD alignment missing from the published 1.1.0 Android native
binary. That commit changes four build/verification files, with no Rust source,
generated API, Cargo manifest or lockfile changes. Its linker option is
`-Wl,-z,max-page-size=16384` for Android targets.

`scripts/rebuild_android_native.py` applies that build option to the exact
1.1.0 source commit `5e451092dba0c1a09ee83ff6e5be37b1152a5c58`, without
changing the checkout. It requires the pinned Cargo.lock and original AAR
SHA-256, uses `cargo build --locked` for API 28 arm64, checks actual ELF LOAD
alignment and offset/address congruence, and compares exported FFI/UniFFI/JNI
names. The output preserves `classes.jar` and every original AAR entry except
`jni/arm64-v8a/libiroh_ffi.so`. An arm64-only APK filter is required: the other
unchanged AAR ABIs are not repaired by this script.

This is a pinned native link repair, not a new transport or a Protocol 4 change.
An exported-name match is useful build evidence, but still requires final APK
ZIP checks, actual generated-FFI/native initialization and device sync tests.
Generated AARs, the source clone, build cache and full reports remain ignored.

### Native dependency security gate

Static triage of the official advisories found that the FFI 1.1.0 lock actually
selects Rust `iroh`, `iroh-base` and `iroh-relay` 1.0.2. The app adapter enables
automatic discovery/relay before Together's signed-session authentication.
Therefore application signatures and the new linker flags cannot protect the
lower transport receive path from
[GHSA-7cq4-mhxw-xw78](https://github.com/n0-computer/iroh/security/advisories/GHSA-7cq4-mhxw-xw78).
The exact old source retains a pending batch when zero segments fit, preventing
receive progress. **Confirmed, high-priority release blocker.** No attack was run
against any real device or public service.

The same lock contains the affected prefix-only mapping from
[GHSA-vwh7-9883-83xj](https://github.com/n0-computer/iroh/security/advisories/GHSA-vwh7-9883-83xj).
The supported typed socket-address path does not reject that reserved range.
**Confirmed limited transport-routing defect**, with no demonstrated identity or
business-data compromise. For
[GHSA-jx4g-cg2x-jc35](https://github.com/n0-computer/iroh/security/advisories/GHSA-jx4g-cg2x-jc35),
the affected derived custom-address deserializer is present, but the App uses
typed endpoint/relay/socket addresses rather than ticket/custom-transport
deserialization. **Needs review for App-level reachability**, not a claimed App
crash reproduction. No root/scoped SECURITY.md policy was resolved; the existing
security-review document and actual adapter configuration define this scope.

[Pinned native source inputs](../../../packages/together-native-source/README.md)
now freeze only the wrapper dependency lock: Rust Iroh/base/relay/dns 1.1.0 and
Noq/proto/udp 1.2.0, with the original FFI wrapper and generated API intact. Lock
SHA-256:
`0904d9b3cc5c1b5c3384f2a8fc8881da91bcee6231ad1c8813a1ae6eaae268e5`.
The upstream fixed source clears a batch with no receive progress and replaces
the unsafe custom-address deserializer. Both final native build inputs now prove
the fixed lock and unchanged wrapper ABI. Final Apple/Android artifact checks
passed; App interoperability still needs validation. The fix is **not verified
as a finished secure release**. The independent review remains a separate gate.

Two exact upstream library regressions were attempted with the unchanged fixed
lock, two jobs and an isolated target. Cargo rejected both before execution:
the dependency packages `iroh` and `iroh-base` require dev dependencies and are
not members of the FFI workspace. These are **NOT RUN / BLOCKED**, not two failed
test assertions or passing reproductions. The lock was not changed to make them
run. Local logs retain both Cargo errors.

An independent developer challenge of the build guard identified index-flag
and output-symlink provenance gaps, without evidence of contamination in the
actual build. The guard was strengthened. Eight isolated source-gate checks
passed: clean approved source, restored legitimate source, hidden/index-skipped
source mutation rejection, ordinary source mutation rejection, arbitrary lock
rejection, symlink output rejection and empty LOAD rejection. The actual shared
source's 145 tracked files and fixed lock also passed direct validation. These
are build-provenance tests, not network vulnerability exploitation tests.

## Reset and privacy

The user separately authorized clearing Together data on the two devices. That
authorization is not a migration test. Root execution archived the prior Mac
state before fresh setup and kept exact recovery details privately. The new Mac
identity survived the actual restart check. Android emulator upgrade preserved
its synthetic profile; Samsung reset/install and recovery are not claimed here.
This report and the artifact inspection tool do not touch device data or keys.

No real device IDs, addresses, invitation codes, user text, private media,
databases, credential paths or signing material belong in this public report.
Artifact binaries, complete logs and screenshots remain in ignored local QA
storage. Do not upload APK/DMG or private backup files as source changes.

## Source-review checkpoint

Developer read-only review of the normal-release changes found separate normal
and QA namespace/root policies, missing-identity rejection when prior storage
exists, verified signed-hello profile names, persisted-profile setup completion,
and read-only native device lists with unsupported enrollment actions hidden.
Normal Mac diagnostics do not export the QA state file. No signed-operation,
merge, ACK or gift-receipt format changed in this release promotion.

This is source inspection, not an independent security audit. The separate
normal Mac startup, Android code 14 failure/code 15 runtime retry, package
inspection and remaining physical gates are recorded above. Imported upstream
source text retains its original formatting; a raw diff check may report vendor
whitespace. Non-vendor changes pass the separate diff check; third-party source
must not be silently rewritten to hide that distinction.

## Current automated regression counts

| Suite | Passed | Failed | Skipped / not run |
| --- | ---: | ---: | --- |
| Swift core, first run without optional integration environments | 142 | 0 | 11 skipped |
| Pinned legacy synthetic store upgrade, separately supplied fixture | 1 | 0 | 0 |
| Safe native Swift transport and persistence | 17 | 0 | 0 |
| Normal Mac launch boundary | 4 | 0 | 0 |
| Kotlin protocol / domain / App policy | 66 | 0 | 3 skipped |
| Portable conformance | 18 | 0 | 0 |
| Relay local-runtime tests | 21 | 0 | 0 |
| Apple native input-provenance tests | 5 | 0 | 0 |
| XCUITest / physical Samsung / normal-release cross-device session | — | — | NOT RUN |

The Swift Testing summary says "153 tests" but includes the 11 skips; it is not
153 passing tests. The separately supplied legacy fixture validates compatible
storage, historical facts and identity reopening, not C1-to-native route migration.
Copy QA: Mac 0 errors / 14 retained warnings; Android 0 errors / 0 warnings.
Android Release lint: 0 errors / 17 warnings, including non-shipped x86 native
libraries; actual shipped arm64 ELF and ZIP alignment pass independently.

## Current decision

**NOT READY FOR A GENERAL STABLE / VPN-FREE CLAIM.** The inspected Mac Build 20
and Android code 15 checkpoints can support a narrowly qualified local test
delivery. Mac setup/restart and Android emulator native invitation/cancel are
tested; normal-release cross-device authentication, Samsung use, independent
no-VPN networking and the independent review remain open. A later commit-stamped
delivery package still needs its own artifact verification and final manifest.
