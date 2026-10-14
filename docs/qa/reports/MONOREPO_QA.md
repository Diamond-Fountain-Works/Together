# Monorepo QA — in progress

Baseline main: `1cb1a22e7f6c601a38d5044a3accd468d49e4071`. Work branch: `refactor/monorepo-foundation`. Public source migration, no installation or production Worker deployment.

Full local `make qa` is running after path consolidation. Completed focused protocol tests: Swift 8 PASS, Python 9 PASS. Pinned legacy source restores byte-for-byte (104 files), and generated legacy-store upgrade passed. Results below will be replaced only with current run evidence, never earlier results relabeled as current.

Desktop UI/visual, final isolated actual-store restart, Universal Release/DMG and GitHub CI are pending. Copy warnings remain visible (0 Error / 13 Warning). Independent cryptographic review, Developer ID/notarization and physical two-Mac/different-Wi-Fi acceptance remain separate and unrun for this refactor.
