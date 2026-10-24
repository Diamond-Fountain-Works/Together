# 0.2.4 platform compatibility QA

## Scope and source

Isolated `feature/platform-compatibility`, based on localization checkpoint
`833d11e96e29973f3916a3e34662ef8b15b51739`. Candidate metadata is Mac/iOS 0.2.4
Build23 and Android0.2.4/code17. Public source only; no production installation,
reset, signed-history rewrite, pairing change, Worker deployment or merge.
The existing 0.2.3 published artifacts are unchanged.

Policy: `packages/together-native-source/platform-support.json`.

| Platform | Configured floor | Actual binary/build | Runtime coverage |
| --- | --- | --- | --- |
| Mac | 11.0, arm64 | Mach-O minimum11 / SDK26.5; sealed ad-hoc App and verified DMG | Physical macOS11 and other M generations NOT RUN |
| iPhone/iPad | 15.0, arm64 | Normal Release and independent QA generic-device build/link PASS, SDK27.1 | Simulator deferred by user; physical iPhone/iPad NOT RUN |
| Android | API24, ARM64 + ARMv7 | Signed optimized APK; actual NDK API24 for both Iroh ELF; all6 libraries 16KiB-aligned | Owned Android15/API35 ARM64 emulator only; API24/ARMv7/16KiB-kernel/physical NOT RUN |

This matrix records minimums and evidence, not a claim that all intervening OS
versions or device models have been exercised. Android/API23 was rejected because
the exact pinned FFI wrapper declares API24. No manifest override was used.

## Actual local results

| Gate | Result | Evidence under ignored local QA directories |
| --- | --- | --- |
| Core Swift | 172 PASS, 0 FAIL, 11 opt-in SKIP | `platform-compatibility/core-final-integration-full.log`, `core-final-counts.json` |
| Pinned old-source SwiftData upgrade | 1 PASS | `platform-compatibility/core-pinned-legacy-final.log` |
| App Combine/session observation | 3 PASS | root `.local-only/compatibility-20261024/mac-ui-observation-tests-final-retry.log` |
| Native P2P regression | 17 PASS | `compatibility-20261024/p2p-tests-final.log` |
| Kotlin JVM | 77 PASS, 0 FAIL, 3 opt-in SKIP | `platform-compatibility/android/android-summary.json` |
| Android emulator instrumentation | 7 PASS | `platform-compatibility/android/instrumentation-api35-resources-fixed.log` |
| Normal optimized Android Release UI | PASS: setup, invitation/cancel, process restart, stable public identity/endpoint | `platform-compatibility/android/release-ui-smoke.json` |
| Native provenance/floor gates | 9 Apple +10 Android +10 SDK/parser tests PASS | `compatibility-20261024/*gate-final.log` |
| QA/review/publication tool regression | 10+7+3 PASS | `compatibility-20261024/{quality,visual,safety}-tools.log` |
| Bilingual resource regression | 23 PASS; 900 Apple /298 Android keys complete | `compatibility-20261024/localization-final.log` |
| Copy | WARN: 0 errors, 28 warnings; Android resources0 errors/0 warnings | `compatibility-20261024/copy-final.json`, `android-copy-final.json` |
| Android lint | Debug0 errors/15 warnings; Release0 errors/17 warnings; no NewApi finding | `platform-compatibility/android/android-summary.json` |
| Mac native XCUITest | NOT RUN: 0 assertions executed, 6 selected methods blocked at automation initialization | `compatibility-20261024/mac-ui-acceptance.json` |
| Visual | REVIEW REQUIRED; Android new local candidate, Mac/iOS runtime capture NOT RUN | Approved baselines unchanged |

The opt-in Core skips include network, crash/performance and old-copy fixtures;
a separately executed focused gate must not be silently counted as part of the
172-pass run. Existing 100k results are not new compatibility performance data.
The three skipped JVM tests require explicit isolated integration orchestration;
they are not phone tests.

Mac UI initially failed to compile a test-only newer clock API. The harness was
fixed without changing product behavior or assertions. Final build-for-testing
and QA host/runner Bundle ID preflight PASS. QA App minimum12/Runner14 use the
current macOS27.0.1 host; they do not pretend to run macOS11. The runner then
reported `Timed out while enabling automation mode`; no test case or screenshot
ran. System debug/accessibility permissions were not changed. Full original
failure logs and an extracted startup error are retained locally.

## Data and identity safety

The existing global SwiftData model names/fields remain intact. Modern opening
uses public metadata and a genuinely read-only preflight before writable access.
An initial empty migration plan alone was insufficient: a synthetic future
same-name model could lose an unknown field. That failed experiment is preserved;
the final guard rejects future schema variants and leaves database/WAL bytes and
future fields unchanged. Known unversioned stores reopen. No private CoreData
SQL/schema parsing or platform hash whitelist is used.

The SQLite backend stores the same canonical signed operations/local records,
uses a Together application marker/version, FULL synchronization and transactions
for log/head/ACK/gift-slot updates. Existing SQLite remains SQLite on newer OS;
an old OS cannot reinterpret an existing SwiftData file as an empty legacy store.
Rebuild, tombstone, duplicate-content rejection, missing ACK/restart and original
media checks use synthetic identities. The pinned original0.0.1 source creates
11 operations; isolated upgrade preserves IDs, Tasks/Wishes/Gifts, avatar,
Relay binding, history and finance/restart behavior. Real user stores were not
opened. Device identity is never silently replaced.

## Build and distribution limits

Xcode27.1's default Mac SDK supports minimum12. An ordinary SwiftPM triple can
therefore be clamped. The builder selects the already installed CLT26.5 SDK,
passes a real frontend/link target11, checks objects/final Mach-O, weak modern
frameworks and the arm64 minimum11 back-deployed Concurrency runtime. No SDK
metadata/binary deployment fields were patched. The native package is rebuilt
from the reviewed source/lock for Mac11 and iOS15; old vulnerable binary fallback
remains forbidden. Android JNA5.19.1 is checksum-pinned and verified through the
real optimized invitation action, not just assembly. Historical JNI fields stay
preserved by R8 rules.

Unsigned generic iOS products cannot be installed or delivered as a signed IPA.
Device signing/provisioning and actual iPhone/iPad testing remain required. The
Mac DMG is ad-hoc and unnotarized; strict codesign verification passes but
Gatekeeper assessment rejects it. This is not Developer ID distribution.

| Retained local artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `apps/apple/macOS/dist/Together-0.2.4-Build23-AppleSilicon.dmg` | 10903552 | `f4e4b982c47602f5d47699104e81de617cfc47f878b9b41776b3a8756fdf3e1c` |
| `qa/results/platform-compatibility/android/Together-0.2.4-17-arm.apk` | 34464699 | `179e68f278920048a366dcc83db289a542d510ada39402c41444af978db4b647` |

No APK, DMG, real database, private key or screenshot candidate is committed to
this Public source repository. iOS generic products are build outputs, not a new
published release. The existing Android signing identity is retained.

The candidate has no approved0.2.4 What's New entry yet. The artifact gate reports
this as a warning; add reviewed bilingual release notes before a public release.
It does not advertise platform runtime tests that have not run.

## Warning disposition and remaining gates

Copy warnings remain visible:27 context-specific equal strings, plus1 independent
security-review boundary. No audit rule or threshold was disabled. Translations
of equal current strings can need different future context; wholesale aliasing
is not part of platform compatibility. This is WARN, not a manufactured PASS.

Unrun: physical macOS11, iOS/iPadOS15, Android/API24, ARMv7, 16KiB-kernel,
public independent-network regression and independent protocol/security review.
The user explicitly deferred iOS simulator initialization/runtime. Successful
local native/Relay tests are not real cross-WiFi or VPN-free acceptance. New
visual candidates require human approval and cannot replace approved baselines.

## Focused network regression and publication safety

- Relay TypeScript check PASS; real local Worker tests21/21 PASS.
- Portable protocol conformance18/18 PASS.
- Four focused Swift C1 tests: initial3PASS/1FAIL, then4PASS/0FAIL/0SKIP
  after correcting only the legacy migration fixture. A fresh unpaired Protocol3
  identity now intentionally takes the partner bootstrap route and already
  activates Protocol4. The old test attempted a second migration and correctly
  received unauthorized. The test now starts with verified legacy pins and waits
  for identical persisted inventory before the explicit migration. No production
  migration authorization check was weakened. The original failure and teardown
  I/O warnings remain in `network/swift-local-relay.log`; final evidence is
  `network/retry-1/swift-local-relay.log` (test execution9.971s).
- Existing Swift–Kotlin native bridge against a real isolated loopback Worker:
  1PASS/0FAIL/0SKIP,5.194s; canonical business results, signed history and original
  media are exercised. This is not GUI or physical/public-network acceptance.
- Both owned Workers stopped. New exact outcome parsing requires one actual
  completed test; a name, skip or duplicated execution cannot satisfy CI.
- Source+all-ref/reflog secret scan passed at the initial staged checkpoint:
  638 tracked files/1161 historical blobs/0 issues. Final scan is retained locally
  and CI repeats it on the published branch. This is credential/data scanning,
  not an independent cryptographic audit.
- `npm audit` reports7 pre-existing development dependency nodes:3high/4moderate
  (`@cloudflare/vitest-plugin`, `@vitest/mocker`, `miniflare`, `undici`, `vitest`,
  `wrangler`, `zod`). All are marked dev in the unchanged lock; there are no npm
  production dependencies. This is still a dependency warning, not a clean
  vulnerability result. No automatic breaking dependency upgrade or production
  Worker deployment was performed. Local full/summary audit files are retained.

The final Apple rebuild increments Build22 to23: iOS protects the candidate's
device files before publishing the model. If protection fails, the startup error
remains visible and no unprotected session is exposed. The previous Build22
candidate is withdrawn locally; Android code17 bytes are unchanged. Final generic
iOS bundle/source checks pass, but protection-failure injection and iOS runtime
remain NOT RUN.

Hosted CI now includes normal+QA generic-device iOS builds and broad Android
native floors; no hosted simulator/UI runtime is claimed. The Draft stacked PR's
Checks show the exact latest-commit results; configuration is not execution.
Task-owned build caches, runtimes and synthetic stores are removed after retaining
these deliverables and minimal logs/JSON/candidate evidence. The local cleanup
manifest records exact targets, reclaimed bytes and final existence checks.
