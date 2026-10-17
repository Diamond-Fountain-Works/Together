# Android Phase B — implementation and verification boundary

Base: Android Phase A `1dfce291ac02726e48717558f48f76f196662032`, independent `feature/android-business-phase-b` worktree. Parent PR #5 is unmerged; this remains a stacked, unmerged client change. No production storage, Apple installation, device keys, Worker or invitation TTL is changed.

## Existing foundations retained

Kotlin/Compose/Room/Keystore and the exact Protocol 4 certificates, anti-entropy, per-device durable ACK and deterministic domain projector remain authoritative. BusinessCommands produces validated operation groups; the repository replays a fresh candidate and commits the full group, Lamport and certificates in one Room transaction. An editor compares unchanged task/expense fields with its opening baseline. New source does not redefine Protocol 3, copy a Mac private key, create a third partner or recompute an existing space.

## Business surfaces

Phone drawer and tablet rail share Home, Our Plans, Wishes, Our Finances, Connection and Settings. One task editor supports assignee/due/regular and flexible recurrence. Wish grants/items/adjustments retain actor roles, beneficiary confirmation and diagnostic quota conflicts. Finances uses exactly Reserves/Expenses/Bills, integer minor units and frozen CNY, same rule revisions/occurrences, and local private card profiles. Ordinary operations are not partner approvals. Original Apple QA/copy/visual states are retained.

Love Gifts have overflow actions and conditional unread notification, no permanent card or destination. Drafts are local; a fresh transactional projection checks daily quota and clock rollback before immutable send. Media manifests plus gift creation commit together. Deletion retains the slot. Shared-zone day calculation and a periodic foreground refresh handle midnight without a rolling 24-hour window. Presentation/opened state is local, independent from receipt and operation acknowledgement. Normal-use arrival never opens a reveal over an editor.

## Original media and existing channel

MediaFiles streams originals under the active workspace's no-backup directory, generates independent preview caches, uses UUID-controlled paths and never honors remote paths. Android validates image headers/a bounded decode and audio format; unsupported/corrupt files fail without publishing a verified marker. Only thumbnails are downsampled. Originals have no application size/pixel cap.

MediaChannel hooks the already authenticated C1 encrypted content type `media`. The existing Codable WirePayload cases are used unchanged: `mediaRequest`, `mediaChunk` (65536 bytes), `mediaComplete`, `mediaVerified`, `mediaFailure`, `giftReceipt`. The Swift UUID-keyed asset hash dictionary is an alternating JSON array. A receiving lease prevents two peers writing a partial file; durable offsets survive interruption. SHA-256/format checks precede atomic commit and content-bound receipt. A socket send, operation ACK or relay forwarding never implies media completion. No server media store/mailbox is added.

Only current profile avatars and effective, undeleted gift attachments are downloaded automatically; a standalone manifest is not a download instruction. Lease admission reserves the combined remaining bytes against actual available filesystem space. Import and every chunk recheck a dynamic 8–128 MiB filesystem reserve for database/OS work. This reserve is not a maximum file size: a large original is accepted whenever current capacity permits, and an interrupted partial can resume after space is freed. No disk-filling test or silent original compression is used.

Provider query/open/read runs outside the repository mutex. Editor dismissal cancels its import job; cancellation signals and closes a blocked provider stream. A result lease takes ownership synchronously before a cancellable dispatcher handoff and removes any completed-but-unpublished original on cancellation/failure. Staging verifies the same active workspace, owner and space before committing the reference. A document provider that ignores platform cancellation cannot acquire the database mutex.

Android SAF selects originals and explicitly exports only verified photo bytes to a user-selected document; the original extension must match. Audio uses explicit Play/Pause/seek, never autoplay. Recording requests the Android microphone permission and stops when the lifecycle leaves the foreground. Software Ed25519 remains AES-GCM wrapped by Android Keystore; this is not a claim that Ed25519 or all local business data is hardware encrypted. Root/key-loss recovery remains an explicit new-device authorization workflow, not silent identity replacement.

## Tests and remaining gates

A real native Swift test process creates independent public descriptors, which the synthetic roots authorize. Two native peers and Kotlin exchange business operations and originals through an actual loopback Worker. Their keys stay in their generating processes. This differs from physical Mac/phone testing. Room, Android media and Compose tests run separately on an isolated emulator; screenshots remain candidates.

The first native offline assertion exposed that the existing Swift full task edit also writes unchanged fields, creating a same-field conflict. The distinct-field test now explicitly emits a title-only native domain operation. Existing same-field deterministic-merge fixtures remain in force. This does not claim that the Mac GUI editor gained field-baseline tracking, and no Mac runtime source was changed.

Tests provision separate synthetic local worlds. Their loopback-only legacy bootstrap fixture uses reserved benchmark source IPs so one shared Worker process does not combine unrelated test worlds into a single V1 rate bucket. Production rate limits and the Worker are unchanged, and the server rate-limit regressions remain mandatory.

Current module results and unfinished work belong in the Phase B QA report. Full physical acceptance, API2 production deployment, independent cryptographic review and candidate visual approval are separate gates. No Android client can guarantee recovery after OS uninstall destroys both its private store and Keystore material.

## Derived review and disconnected UI

Review pages contain at most 16 rows. Only the requested rows replay logical prefixes off-main to show effective quantities, wish confirmation and forecast-derived expense values; gift rows stay sealed metadata. This adds bounded audit work, not an incremental projection/100k performance claim. Explicit confirmation freezes the projected amount/payment in a new operation, including values that were derived from the forecast.

Recoverable transport errors belong in Connection with automatic retry and a manual Retry action. Local command/storage failures remain actionable dialogs. Socket failure does not block cached gift presentation or offline local CRUD, nor stack a network modal over a sealed reveal. Dedicated runtime QA removes the test adb reverse to exercise this boundary and restores it in finally.
