# Monorepo migration and rollback

## Gate and checkpoints

Build 4 local-install preparation was completed before repository changes: original Pinyin UI 14 PASS / 0 FAIL / 1 intentional SKIP; 68 user-approved screenshots; old-source and actual copied-store upgrade/restart PASS. Separate independent security review, notarization and real two-Mac Wi-Fi acceptance remain pending.

Organization repository is **Public**, as explicitly corrected/confirmed by the user: `Diamond-Fountain-Works/Together`. Original verified baseline on `main`: **1cb1a22e7f6c601a38d5044a3accd468d49e4071**. Checkpoint tag: `checkpoint/pre-monorepo-build4`. Existing finance and QA branches were preserved and pushed. No unverified formal `v0.0.1`/`v0.2.1` release tags were invented. Refactor branch: `refactor/monorepo-foundation`; do not merge before reviewing its PR and regression evidence.

## Git history protection

Original object directory was `~/.cache/Together/finance-development.git`. All objects, references, config and reflogs were copied to stable owner-only `~/Documents/RepositoryBackups/Together/20261014-140248-before-github/complete-git-directory`. The backup includes five recoverable historical commits, including one reflog-only amended commit; a ref-only bundle alone would miss that amended history. Original untracked work/patches were separately backed up. `fsck`, restored-reference/reflog/history/status comparisons passed before creating the standard project `.git/` copy. The source cache directory was retained; it is no longer authoritative.

Additional `pre-monorepo-baseline.bundle` contains all current refs and was verified. Original external directory and all verified backups remain. No init/reset/clean/force-push/history rewrite occurred. Future backups must include all refs and, when needed, reflog-only recovery objects; keep them outside cache/repository and verify before deleting any old copy.

## Path ownership

| Before | After |
| --- | --- |
| `0.2.1/Sources/TogetherApp` | `apps/apple/macOS/Sources/TogetherApp` |
| `0.2.1/Tests/TogetherUITests` | `apps/apple/macOS/Tests/TogetherUITests` |
| `0.2.1/{Together.xcodeproj,Configuration,script,Package.swift}` | `apps/apple/macOS/` equivalents |
| `0.2.1/Sources/TogetherCore` | `packages/together-core-swift/Sources/TogetherCore` |
| `0.2.1/Tests/TogetherCoreTests` | `packages/together-core-swift/Tests/TogetherCoreTests` |
| `server/` | `services/relay/` |
| `qa/migration/legacy_fixture` | `tests/integration/legacy_fixture` template/harness |
| Root authoritative requirements/architecture/finance/design/security/test/phases/changelog | `docs/{product,architecture,domains,design,security,qa,roadmap,releases}/` |
| Tracked QA reports in `qa/` | `docs/qa/reports/` |
| `0.0.1/ICON_COMPOSER.md` | `docs/design/ICON_COMPOSER.md` |

`qa/project.json` is the tooling path authority; scripts resolve from their repository root, not one user's absolute worktree. README and AGENTS are root entry points, not duplicate specifications. UI copy remains one String Catalog in TogetherCore plus native InfoPlist catalog/review index. Approved images and frozen approval metadata stay in `qa/visual/`; result bundles/candidates stay ignored.

## Legacy source restoration and safe removal

`tests/integration/legacy_source.json` pins actual legacy commit **4231afb3a5e911f1095f6c5314c95a0630c736ca**, subtree `0.0.1` and its exact tree hash. Before removing tracked duplicates, all 104 archived files matched the old worktree bytes and the actual old-source-created store passed upgrade against the new core.

`scripts/legacy_source.py` restores that tree with `git archive` into a private temporary directory, validates paths/types (no symlinks/traversal), renders the harness Package template and removes only its own temporary output afterward. Full Git history is required; a shallow checkout missing the pinned commit must fail, never silently substitute new source. Historical original core/avatar/icon material is preserved in Git. Local ignored old app/DMG/cache artifacts were not deleted and do not define current source authority.

`0.2.1` current tracked source was moved, not discarded. Existing product Swift, resources, UI tests and Relay runtime/tests are byte-preserved; generated Xcode references, manifests, version metadata and tooling paths changed. The actual hash-preservation record and regressions are local `qa/results/monorepo-source-preservation.json` and [QA report](../qa/reports/MONOREPO_QA.md).

## Platform and runtime boundaries

TogetherCore keeps module/product `TogetherCore` and current SwiftData/Network/AppKit adapters; its extraction does not imply Android/iOS/watchOS builds pass. Platform-neutral schemas and synthetic vectors live under `protocol/`; future Kotlin domain implementations must pass the same vectors. No placeholder platform projects were generated.

App identity `com.together.app`, Application Support paths, physical schema classes, signed logs, key files, paired pins/routes, C1 transport and Lamport semantics stay unchanged. Build increments to **5**, Marketing Version stays **0.2.1** because package/resource identity may change the binary. No `/Applications` replacement or public release artifact upload. Release packaging is validated locally and remains ad-hoc/unnotarized.

Implemented invitation TTL stays **600000 ms (10 minutes)**. Formal requirement **28800000 ms (8 hours)** is unresolved and tracked in [Issue #1](https://github.com/Diamond-Fountain-Works/Together/issues/1); change it only in a separate coordinated network PR/test/deployment. No production Worker configuration/deployment was changed. C2 and encrypted mailbox are future boundaries, not current capabilities.

## Rollback

Keep `main`/checkpoint and the external backups intact. Review/reject the refactor without merging. To inspect the original baseline safely, use `git worktree add --detach <new-private-directory> checkpoint/pre-monorepo-build4`; build only, without install or production data. Restore old migration source via the pinned helper, not a version-folder copy added to active source. For repository recovery, restore the verified full Git directory into a separate worktree and run `git fsck --full`/reference comparison before pointing tools at it. Never reset the live worktree or replace production stores/keys to resolve a path/build failure.
