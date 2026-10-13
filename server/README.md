# Together Connection Service

Cloudflare Workers + SQLite Durable Objects. `ConnectionDirectory` stores short-lived challenges, invitation hashes, public device descriptors and route membership; `RelayRoom` maintains hibernating online sockets and forwards bounded frames. It does not replay operations, decide business state, store media files or provide offline delivery.

## Local development

Node 22.16+; exact dev dependencies and lockfile are in this directory.

```sh
npm ci --legacy-peer-deps
npm run check
npm test
npm run dev
```

Local endpoint `http://127.0.0.1:8787/health`. It reports `delivery: realtime-only`. `npm test` runs the real local Workers runtime (not a deployed account). Swift local integration uses `TOGETHER_RUN_RELAY_TESTS=1 swift test` after the dev service is ready. Debug accepts HTTP only on loopback; release requires HTTPS/WSS.

## Client configuration

The native app receives the public service origin via its `TogetherRelayURL` Info.plist key. The verified origin is persisted in `0.0.1/Configuration/RelayService.json` and used by every default project generation/build via the explicit Info.plist template. The build script verifies the actual bundle origin and signature before staging. Developers may override with `TOGETHER_RELAY_URL=https://<verified-service-origin>` and the existing native build script. It is a public origin, never an API token/password. Normal users do not enter IP addresses, install Tailscale or configure the service in Terminal. If no origin is configured, the app states the service is unavailable and retains local editing; do not distribute that build as a completed network release.

## Deployment

Use official Wrangler OAuth (`npx wrangler login`) or a scoped Cloudflare API Token supplied securely outside Git. Account/password is not a Workers API credential. Never store passwords, tokens, OAuth URLs or complete invitation codes in project logs/configuration. `.dev.vars` and `.env` are ignored, but this service currently requires no application server secret: server challenges/tickets are securely random and only hashes of invitations/tickets persist.

After account authorization, verify `npx wrangler whoami`, run tests/checks, then `npm run deploy`. The configured SQLite DO migrations create two namespaces; do not rename/delete them to resolve a deployment problem. Confirm the returned HTTPS origin `/health`, then run two isolated Swift clients against that origin before putting it into the native release bundle. Public deployment does not equal different-Wi-Fi dual-Mac acceptance.

OAuth consent that grants new security-sensitive account permissions requires explicit approval. MFA/CAPTCHA/account terms must be handled as required by the account flow. Do not bypass browser security warnings. If deployment fails, record the actual CLI status, inspect account/Workers/DO permissions and migration conflicts, and keep the local artifact/test evidence; never invent a successful URL.

## Protocol and lifecycle

HTTPS authentication: 60-second one-use server challenge, Ed25519 signature over domain tag, challenge, method, path, body SHA-256 and device ID. Descriptor/key/device binding is checked. Rate limits cover all requests, creation and incorrect joining. Invitations: 12 random base32 characters (60 bits), 10-minute expiry, atomically consumed once. Used/expired/unknown share one public error. Old-device migration pins must match before invitation consumption.

Joining yields pending membership. Both clients verify signed ephemeral handshake/SAS and explicitly consent. Both server confirmations must bind the same transcript before encrypted frames can forward. New pairing/relay binding is committed locally only after both signed peer consents. Reconnect obtains fresh one-use 60-second socket tickets; no bearer token in a URL. One active socket per member; old sessions close.

Handshake/public routing metadata is visible to the relay; operations, gifts and media are application-encrypted with authenticated per-session keys. See `SECURITY_REVIEW.md`: CryptoKit primitives are mature, application framing still needs independent review. The service can observe metadata, availability and traffic sizes or deny service. No server-held plaintext shared-space key exists.

Max frame 524,288 bytes; 200 frames/second/socket, 8 KiB handshake/control frame cap. Clients use stop-and-wait 64 KiB media requests and streaming hashes; this is not a total image-size/resolution cap. Real platform throughput/quotas apply. Cloudflare limits and behavior must be checked before production-scale changes.

Expired challenges/tickets/invitations/pending routes are cleaned by alarms. Paired public routing metadata persists until authorized revoke. `/v1/routes/<id>/revoke` requires a current member signature and closes sockets, without changing either local database. No encrypted mailbox exists: when the partner is offline, content is not queued or stored here. Future mailbox needs separate encrypted storage, TTL/acknowledgement, media object storage/cost/lifecycle design.

## Status and operations

Use `/health`, Wrangler deployment status and Dashboard DO metrics. Application code does not log invitations/content; production observability is disabled by default. Enable carefully scoped diagnostic metadata only after a privacy review. Do not turn on request-body logging. Keep credentials in Wrangler's secure account configuration or a scoped environment secret outside the repository.

Primary references: [Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/), [hibernating WebSockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/), [Workers Vitest integration](https://developers.cloudflare.com/workers/testing/vitest-integration/).


## Current deployment evidence (2026-10-10)

The account OAuth grant was explicitly approved with account/user read, Workers/Scripts/Routes write and background refresh, using Wrangler's encrypted account file with its key in macOS Keychain. No password/token was added to server or Swift source. The first attempt was refused with email verification error 10034. After the user completed verification, the service was deployed successfully: https://together-connection.together-connection-service.workers.dev. Version ID d214ea2f-5034-4b1a-9f31-dca118b1b245; `/health` returned HTTP 200, protocol 1, realtime-only. Two isolated native clients completed actual HTTPS/WSS pairing, encrypted operations, profiles/wishes, original avatar/photo and audio chunks, acknowledgements, reconnect and restart persistence. This is a public-service integration test on one Mac, not a real different-Wi-Fi dual-Mac acceptance. Independent protocol review and physical acceptance remain pending.


Public integration command (one Mac, temporary data only):

```sh
cd ../0.0.1
TOGETHER_RUN_RELAY_TESTS=1 TOGETHER_RELAY_TEST_URL=https://together-connection.together-connection-service.workers.dev swift test --filter RelayIntegrationTests
```

Only generated fixture content is sent in this check; production data and Keychain identity are not opened. Server membership metadata follows the normal authorized route lifecycle; no fixture business text/media is persisted on the relay.
