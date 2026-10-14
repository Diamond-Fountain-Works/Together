# CI scope

`.github/workflows/quality.yml` runs on normal push/PR and manual dispatch with read-only repository permissions and pinned action commits. It never deploys Workers, publishes a release, installs Together or uses production database/identity/Cloudflare credentials.

- `macos-26`: Swift tests, old-source generated-store upgrade, native local WebSocket integration against a fresh loopback Worker, native Debug build, copy/protocol/publication gates. Full Git history is fetched to restore the pinned legacy source. Synthetic QA logs expire after 7 days.
- `ubuntu-24.04`: relay typecheck and local Workers runtime tests; JSON Schema/conformance, QA tool tests, copy and tracked/history safety audit.
- Copy warnings remain visible. `check_ci_report.py` requires each headless gate to pass and UI/visual to be honestly NOT RUN; review-required independent cryptographic review cannot become a CI PASS.
- XCUITest/screenshots run locally with a usable logged-in macOS desktop via `make qa`. Hosted CI is not configured to provide the approved input-method/screen/environment baseline. No hosted UI/visual PASS is claimed.
- Real two-Mac/different-Wi-Fi tests and independent protocol review are manual gates. Android CI will be added only when a real Android project exists.

Runner choice follows [GitHub hosted runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); `macos-26` is used instead of the Xcode 27 preview label. Native package minimum is Swift 6, deployment macOS 14. Reproducible UI baselines remain tied to their recorded local macOS/Xcode environment, not the runner image.

Local logs live under ignored `qa/results/`. Approved images and metadata live under `qa/visual/approved/`, reviewed synthetic snapshots under `qa/visual/reviews/`; scripts never automatically overwrite them.
