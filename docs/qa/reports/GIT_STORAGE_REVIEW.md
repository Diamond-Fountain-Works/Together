# Git storage audit — final QA, 2026-10-14

The dedicated repository is intentionally outside the worktree:

- Git directory: `/Users/giga_fortress0/.cache/Together/finance-development.git`
- `core.worktree`: `/Users/giga_fortress0/Documents/ProjectsLocal/Together`
- Initial branch: `feature/our-finances-v0.2.1`; this QA uses `qa/final-v0.2.1-build3`.
- Baseline: `4231afb3a5e911f1095f6c5314c95a0630c736ca`.
- Finance Build 2 checkpoint: `f2b362b21d4e72baf21d2f19b2e3b4f7f581fc1e`.
- `git fsck --full` passed; both original commits/trees are reachable. There is no configured remote. This repository starts at the checkpoint; it does not establish earlier development history.

Risk: `.cache` is not a durable history location. A cache-cleaning tool can remove all objects, refs and commits while leaving source files intact. No remote recovery is configured. No history directory was moved or deleted in this task.

## Proposed migration — requires a separate authorized action

1. Quiesce Git writers; record refs, HEAD, object count and current uncommitted/untracked files. Preserve all user work.
2. Create an all-refs bundle in an explicitly chosen durable directory outside `.cache`; verify the bundle. Do not publish it or include credentials.
3. Copy (do not move) the external Git directory to the project’s `.git`. Update the copied `core.worktree` configuration to the project directory; do not change the existing external repository yet.
4. Compare `show-ref`, `rev-list --all`, HEAD, tracked tree hashes and worktree status between both copies; run `fsck --full` on the copy and verify the bundle again.
5. Verify ordinary `git -C <project> status/log` resolves the copied repository, rather than the parent home-directory repository. Confirm all branches/checkpoints and local changes survived.
6. Keep the original external history until the user explicitly authorizes retiring it. A private remote is an optional additional recovery path, not a prerequisite or an automatic upload.

The repository migration remains proposed and was not executed. The all-refs backup step was separately authorized and completed as recorded below.

## Authorized durable backup — 2026-10-14

- Bundle: `/Users/giga_fortress0/Documents/RepositoryBackups/Together/20261014-124748/Together-all-refs.bundle`.
- SHA-256: `c4867fcb89087a7af6964ac3a9520507744bb3ad8f34191f7adf2443740b0e03`.
- Source `fsck --full`, `bundle verify`, temporary mirror restore and restored `fsck --full`: PASS. All 3 reachable commits and every branch/ref matched.
- Bundle and manifest are owner-only, outside `.cache`. No user database, device key, pairing or credential was copied into the bundle. No upload or remote was configured.
- Tracked worktree was clean at backup. Existing untracked QA documents/images are enumerated in the backup manifest; they are not claimed as Git history.
- The `.cache` source remains vulnerable to deletion, but a verified durable recovery copy now exists. Moving/copying the live Git directory into project `.git` still needs explicit authorization.
