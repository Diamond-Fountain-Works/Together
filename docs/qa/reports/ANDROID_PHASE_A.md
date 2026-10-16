# Android Phase A — engineering evidence

Development baseline: `eff5f8420728470ca2d9444f54a39e356537b953`, independent branch `feature/android-foundation`, worktree `Together-Worktrees/android-foundation`. Repository stays Public. PR #2/#3/#4 were OPEN/Draft; no parent branch, merge, production service, installed Mac App or real user store was changed.

| Gate | Result | Evidence / limits |
| --- | --- | --- |
| Native Debug APK | PASS | `make android-qa`; actual APK under `apps/android/app/build/outputs/apk/debug/app-debug.apk`; debug RSA/v2 signature verified, not a production Android signing identity |
| Kotlin JVM | PASS | 30 tests: protocol 14 (including live local C1), domain 16. >10k bidirectional facts, collisions, keys/revocations, exact ACK, money/AA/calendar/bill/quota/merge, shared vectors |
| Android runtime/UI | PASS | 7 tests on dedicated `Together_PhaseA_QA_API35`, Android 15/API35 ARM64; Room/Keystore/transaction recovery, task flow, independent enrollment/retained data and Room-backed actual local C1 |
| Native Swift regression | PASS, 3 SKIP | 138 PASS / 0 FAIL / 3 explicitly skipped performance/export cases; includes 2 new native Kotlin compatibility tests. No Mac GUI automation or App launch |
| Existing Relay/Python | PASS | Existing Relay typecheck/tests and 17 portable conformance tests passed in `./scripts/qa.sh --skip-ui` |
| Migration | PASS (isolated) | Original 0.0.1-source fixture → current SwiftData generation retained. Android is a new Room schema, not a migration of production Apple storage. Namespace enrollment preserves user/space/key/binding across reopen and refuses overwriting local tasks |
| Copy | Android PASS / Apple WARN | Android exact XML review + audit; Apple 0 errors / 14 existing individually dispositioned warnings retained, independent security disclosure still pending |
| Lint | WARN | Actual lint build succeeded; pinned dependency upgrade advisories remain visible. No rule/baseline suppression |
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

This is a tested development foundation and Debug APK, not production Android/network release approval. Latest artifact hash, screenshots and GitHub/CI links are appended after final capture/publication.

Initial hosted Android workflow failed before compilation because that runner did not expose `sdkmanager`. The follow-up CI bootstrap reuses an existing SDK when available, otherwise fetches the official Linux command-line tools with a pinned SHA-256 before installing only required components. This is CI setup, not an App/network failure; latest hosted result is reported separately. Standard Windows wrapper line endings are normalized in Git via `.gitattributes`, preserving CRLF on Windows.
