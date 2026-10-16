# Android Phase A — engineering evidence

Development baseline: `eff5f8420728470ca2d9444f54a39e356537b953`, independent branch `feature/android-foundation`, worktree `Together-Worktrees/android-foundation`. Repository stays Public. PR #2/#3/#4 were OPEN/Draft; no parent branch, merge, production service, installed Mac App or real user store was changed.

| Gate | Result | Evidence / limits |
| --- | --- | --- |
| Native Debug APK | PASS | `make android-qa`; actual APK under `apps/android/app/build/outputs/apk/debug/app-debug.apk`; debug RSA/v2 signature verified, not a production Android signing identity |
| Kotlin JVM | PASS | 31 tests: protocol 15 (including live local C1), domain 16. >10k bidirectional facts, collisions, keys/revocations, exact ACK, money/AA/calendar/bill/quota/merge, shared vectors |
| Android runtime/UI | PASS | 7 tests on dedicated `Together_PhaseA_QA_API35`, Android 15/API35 ARM64; Room/Keystore/transaction recovery, task flow, independent enrollment/retained data and Room-backed actual local C1 |
| Native Swift regression | PASS, 3 SKIP | 138 PASS / 0 FAIL / 3 explicitly skipped performance/export cases; includes 2 new native Kotlin compatibility tests. No Mac GUI automation or App launch |
| Existing Relay/Python | PASS | Existing Relay typecheck/tests and 17 portable conformance tests passed in `./scripts/qa.sh --skip-ui` |
| Migration | PASS (isolated) | Original 0.0.1-source fixture → current SwiftData generation retained. Android is a new Room schema, not a migration of production Apple storage. Namespace enrollment preserves user/space/key/binding across reopen and refuses overwriting local tasks |
| Copy | Android PASS / Apple WARN | Android exact XML review + audit; Apple 0 errors / 14 existing individually dispositioned warnings retained, independent security disclosure still pending |
| Lint | WARN | Actual lint build succeeded with 0 errors / 15 warnings (dependency/AGP upgrade advisories and unused resources). No rule/baseline suppression |
| Visual | REVIEW REQUIRED | Android screenshots remain local candidates, no approved Android baseline. Existing Mac visual states are not changed or called PASS by this task |
| Security | Source gate + regression, independent review BLOCKED | Tracked files/all recoverable history checked before push; no user DB/media/private keys/credentials/APK included. Not an independent cryptographic review |
| Physical acceptance | NOT RUN | User chose not to connect a phone. No real phone/tablet, Mac↔Android or different-Wi-Fi claim |
| Production | NOT RUN | No API2 deployment, real-user activation, release upload, Mac installation or PR merge |

## Commands and retained local evidence

- `TOGETHER_LOCAL_RELAY_URL=http://127.0.0.1:8796 make android-qa`
- `apps/android/gradlew -p apps/android :app:connectedDebugAndroidTest -Ptogether.testRelay=http://127.0.0.1:8796`
- `TOGETHER_ANDROID_RESPONSE_PATH=... swift test --package-path packages/together-core-swift --filter AndroidPhaseAConformanceTests`, followed by Kotlin with the same generated response file.
- `./scripts/qa.sh --skip-ui` (business/migration/local relay/build PASS, UI/visual NOT RUN, security REVIEW REQUIRED).
- Runtime output is local/ignored: Gradle `build/test-results`, `build/outputs/androidTest-results`, `qa/results/android-phase-a`, `qa/visual/candidates/android-phase-a`. Public report contains aggregate synthetic evidence only.

Existing JDK21/SDK35/36/build tools/Gradle8.13 were reused. Only missing emulator 37.2.12 and Google APIs Android35 ARM64 image were added; the AVD/state is isolated under ignored QA output. No Chinese input method, Accessibility or Developer Tools permission was changed.

## Errors actually corrected

- Java/Kotlin bytecode-target mismatch: both use 17 under JDK21.
- Bidirectional inventory could finish before learning a peer's final union: preserve mid-pass hints and repeat pinned anti-entropy passes; exact partner ACK now checked after convergence.
- HTTP server DTOs contain additive routing metadata: decode recognized fields like Foundation while verifying canonical signed DTOs, not untrusted extra claims.
- Ordinary native surfaces inherited purple Material tokens: warm neutral/rose surface tokens replace those defaults; duplicate Home state prose/device-model heading removed.
- Test IDs/actions select only the newly created synthetic task; isolated Runner rejects production package/physical hardware. Debug-only namespaces and injected clocks test real enrollment/Room without overwriting app state.

## Known unfinished work

Full Android Wishes/Finances/Gift/media editors and original attachment transfer; complete SAF exchange with a physical Mac/phone; phone min-API28/runtime/tablet hardware; 100k Android profiling; control-history paging/root-loss recovery; independent protocol/security review. Current owner-root-only grant/revoke cannot be silently expanded on Android. Real-time Relay needs both devices online; no offline mailbox. Existing Mac visual review and the independent 8-hour invitation PR remain unchanged.

This is a tested development foundation and Debug APK, not production Android/network release approval.

Initial hosted Android workflow failed before compilation because that runner did not expose `sdkmanager`. The follow-up CI bootstrap reuses an existing SDK when available, otherwise fetches the official Linux command-line tools with a pinned SHA-256 before installing only required components. This is CI setup, not an App/network failure; latest hosted result is reported separately. Standard Windows wrapper line endings are normalized in Git via `.gitattributes`, preserving CRLF on Windows.

Foreground hardening serializes repeated client starts, joins a cancelled session before opening another, and uses atomic StateFlow updates so connection changes cannot overwrite a new projection (or vice versa). A delayed-HTTP regression proves concurrent starts do not open two sessions. Clean Linux CI also exposed parent POM/BOM files absent from the warm Mac cache; their official Maven hashes were added without relaxing strict dependency verification.

## Final local evidence — 2026-10-16

Application source commit: `fd7313e5ee46bb4699ae234a69695e2c3a15cc0f`. Subsequent documentation-only commits do not change this APK.

- APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`, 37,980,651 bytes (36.22 MiB), SHA-256 `c8d35f118fb88f6323f892d99f6b7055d2a4c22e8f60125d9dea23ac2e9b9534`.
- Package `com.together.android.debug`, version `0.2.1-phaseA` / code `1`, minimum API 28 / target 36. `apksigner verify --verbose --print-certs` verifies Signature Scheme v2 with the local Android Debug RSA certificate. This is not a production signing/release identity.
- Forced strict-verification compilation/lint completed; the final source then passed 31 Kotlin JVM tests, including the explicit local Worker integration and CryptoKit-response vector. The final 7 connected tests passed after the dark-button correction. Instrumentation XML is preserved under ignored `qa/results/android-phase-a/instrumentation-final-color/`.
- Installed and launched this exact APK on dedicated Android 15/API35 ARM64 emulator `Together_PhaseA_QA_API35`. The user deferred physical-phone testing. No physical handset/tablet or actual Mac↔Android session was used.
- 17 final native screenshot candidates: empty/populated tasks, editor, process restart, Home, Connection, device enrollment, Settings, Light/Dark, 1.3 font scale, animations disabled, tablet-width rail and two Chinese-language views. Local index: `qa/visual/candidates/android-phase-a-final/index.html`; exact image hashes: adjacent `manifest.json`. All remain CANDIDATE / REVIEW REQUIRED; no Android baseline is approved. Earlier exploratory images are not the final evidence set.
- Process force-stop/reopen retained the synthetic task and identical wrapped-identity file hash. Final captures have a complete visible system status bar; the earlier exploratory clipping was not reproduced, and its cause is not established. Emulator locale, font, animation, viewport and night-mode overrides were restored after capture.
- Source publication scan at the application commit: 458 tracked paths, 708 historical blobs, 0 findings. It covers all recoverable refs/reflogs, not ignored/private user storage. Public code contains no APK, screenshots, runtime store or real identity. This is a publication gate, not independent security approval.

[Draft stacked PR #5](https://github.com/Diamond-Fountain-Works/Together/pull/5) targets `feature/gitlike-c1-multidevice` (#4), not the pre-Monorepo main. Repository remains Public. Latest hosted CI belongs to the PR's exact head SHA; earlier failed SDK/metadata attempts remain visible and must not be reported as passing. The workflow runs the APK/JVM/local-Worker/copy/source gates, not Android instrumentation or physical-device tests. Current checks are available on the PR; no merge or deployment is implied.

At application commit `fd7313e`, hosted [Android Linux build/JVM/local C1](https://github.com/Diamond-Fountain-Works/Together/actions/runs/38872556929) and [Monorepo quality](https://github.com/Diamond-Fountain-Works/Together/actions/runs/38872556938) passed. Documentation publication is checked again at the final PR head. No strict-verification rule was disabled to obtain these results.
