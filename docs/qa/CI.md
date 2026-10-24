# CI scope

`.github/workflows/quality.yml` runs on normal push/PR and manual dispatch with read-only repository permissions and pinned action commits. It never deploys Workers, publishes a release, installs Together or uses production database/identity/Cloudflare credentials.

- `macos-26`: Swift tests, old-source generated-store upgrade, native local WebSocket integration against a fresh loopback Worker, native Debug build, copy/protocol/publication gates. Full Git history is fetched to restore the pinned legacy source. Synthetic QA logs expire after 7 days.
- `ubuntu-24.04`: relay typecheck and local Workers runtime tests; JSON Schema/conformance, QA tool tests, copy and tracked/history safety audit.
- Copy warnings remain visible. `check_ci_report.py` requires each headless gate to pass and UI/visual to be honestly NOT RUN; review-required independent cryptographic review cannot become a CI PASS.
- XCUITest/screenshots run locally with a usable logged-in macOS desktop via `make qa`. Hosted CI is not configured to provide the approved input-method/screen/environment baseline. No hosted UI/visual PASS is claimed.
- Real two-Mac/different-Wi-Fi tests and independent protocol review are manual gates. Android build/JVM/lint, native Release verification and Swift–Kotlin integration are configured in `.github/workflows/android.yml`; instrumentation there is compilation-only, not hosted device acceptance.

Runner choice follows [GitHub hosted runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); `macos-26` is used instead of the Xcode 27 preview label. Native package development uses Swift 6; runtime floors are defined in `packages/together-native-source/platform-support.json` and verified against actual binaries. Reproducible UI baselines remain tied to their recorded local macOS/Xcode environment, not the runner image.

Local logs live under ignored `qa/results/`. Approved images and metadata live under `qa/visual/approved/`, reviewed synthetic snapshots under `qa/visual/reviews/`; scripts never automatically overwrite them.

Native XCTest exports now use a unique `qa/visual/candidates/<run timestamp>/` directory and per-image SHA-256 in the run report. Comparison rejects replaced or escaped images; a later focused/failed run cannot silently overwrite a full run's evidence. Snapshot timing/hover assertions remain separate from the image-difference threshold and human baseline approval.

The Xcode 26 CI run exposed a fixture-only SwiftPM compatibility issue: `main.swift` also declared `@main`. Renaming the harness entry to `LegacyFixtureMain.swift` fixed it; current product sources and the pinned old-source tree were unchanged. Run `38527602870` then passed both jobs. This is distinct from local Xcode 27 validation and from manual two-Mac tests.

## Replication 4 headless additions

Stacked PRs targeting refactor/monorepo-foundation now trigger the same workflow. The macOS job additionally requires four actual native Swift clients against a fresh loopback Worker and synthetic SIGKILL recovery. Both V1 and V2 integrations have distinct gates. Portable tests include the signed V4 DTO vectors in Swift/WebCrypto/Python; no deployment credentials are required. The optional 100,000-operation benchmark runs locally and is not a CI throughput SLA. The dedicated QA-host bundle isolates UI startup from production storage; hosted screenshots remain NOT RUN.

## 0.2.4 compatibility gates

The Apple native job rejects incorrect policy, source provenance, slice layout,
Mach-O minimum/platform and malformed SDK metadata. The device-only iOS job
source-builds Mac+iOS slices and compiles both normal and QA iPhone/iPad targets
with minimum15. It does not initialize, boot or screenshot a simulator, provide
provisioning, install an IPA or claim runtime coverage.

Android Release CI source-builds API24 ARM64 and ARMv7 and verifies actual ELF
architecture, NDK minimum and16KiB segments/ZIP alignment. The ephemeral CI signing
key and APK are never published as distribution artifacts. Unit tests cover
malformed/conflicting metadata rather than trusting declarations. Hosted results
and the local API35 emulator run remain separate.
