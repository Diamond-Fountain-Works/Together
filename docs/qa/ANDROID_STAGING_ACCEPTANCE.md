# Isolated C1 API 2 public-network acceptance plan

Status: **NOT DEPLOYED / authorization required**. USB reverse proves a physical Android client
talks to native Swift through a local Worker; it does not prove public DNS/TLS/WSS, carrier reachability,
cross-WiFi routing, latency or production Durable Object migration.

## Isolation and deployment boundary

Use a separate Worker name, for example `together-c1-acceptance`, and its own Workers.dev HTTPS/WSS
origin. Its `ConnectionDirectory` and `RelayRoom` Durable Objects must be created under the new
Worker's own namespace/migration history. Do not bind production namespace IDs, production routes,
service bindings or custom domains. Do not reuse production storage, bindings, secrets or identities.
Use the current checked-in API2 server at a pinned reviewed commit, with the same frame/connection/
rate limits. Do not modify the existing production Worker or the independent invitation PR #3.

Review-only template: `services/relay/wrangler.staging.jsonc.example`. If deployment is later
authorized, a reviewed copy can live beside it as ignored `wrangler.staging.local.jsonc` so its
relative source path stays correct. This stage does not run `wrangler deploy` with either file.

Before any deploy, review a rendered isolated Wrangler configuration, selected Cloudflare account,
the exact source SHA, new namespace names and rollback command; obtain separate user authorization.
Authorization of local tests or GitHub push is not deployment permission. Independent protocol review
remains a formal network-release gate even if a staging experiment is separately authorized.

No mailbox, R2, business database or media storage is added. Durable Objects keep only routing,
authorization and current connection metadata. Business facts and original media stay on clients.
Service credentials stay in local secure Wrangler configuration or CI secrets, never the client/repo.

## Client preparation

1. Use `com.together.app.qa` (explicit `--ui-testing`, fresh isolated root) on Mac, and the separate
   `com.together.android.debug` test installation on the identified phone. Fail closed if a production
   app/store/identity would be selected. Never bundle the staging origin into a normal release.
2. Create two new synthetic partner roots and authorize the Android's independently generated key
   with the existing signed offer/request/completion. Compare fingerprints on both devices.
3. Pin both test clients to the isolated origin; record root/space/device public fingerprints, app
   version, protocol4/API2, OS versions and network types. Never export private keys.
4. Remove only this run's adb reverse. Mac uses WiFi; Samsung uses mobile data or a genuinely separate
   WiFi. Do not claim cross-network acceptance while USB forwarding remains active.

## Acceptance matrix

- HTTPS health and authenticated challenge/ticket; WSS upgrade and mutual signed encrypted handshake.
- Same-user Mac/phone plus partner root; initial history and simultaneous live updates.
- Tasks both directions, concurrent offline field edits, duplicate IDs, tombstones, stable full-log
  count/content digest, and independently verified per-device durable ACKs.
- Frozen CNY and AA, negative reserves, one recurring bill/month instance, Wish fulfillment once.
- Originals larger than a frame, SHA equality, interrupted media resume, separate content receipts.
- Foreground/background/force-stop/reopen; WiFi/mobile transition, WS close and server restart.
- Revoke phone, require new tickets/access to fail, keep lawful prior facts and device identity.
- Capture phase timings/errors and packet/frame sizes without payloads, complete invites or keys.

No server-send or socket success is called Delivered. The sender must stay online until remote
persistence/media acknowledgement; no offline server delivery is promised.

## Rollback and evidence

Stop the two isolated test clients and remove their staging setting. If the new Worker is unhealthy,
roll back **only its** deployment to its prior staging version; on its first deployment disable that
new test Worker. Never roll back production or delete its Durable Objects. Retain sanitized staging
configuration, source SHA, test matrix, timings and scoped logs locally. Review account quota/cost
before testing large media. Cleanup of synthetic staging namespaces is a separate explicit action.

Actual Mac GUI, mobile-carrier/WiFi, four physical devices and public API2 remain **NOT RUN** until
that environment is authorized, deployed and exercised. Local success is not a substitute.
