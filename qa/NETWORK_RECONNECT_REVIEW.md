# Build 3 reconnect regression review

## Observed failure

The first full final-QA run executed UI tests, but a real local Worker/WebSocket business case failed on reconnect with `对方配对确认签名不匹配` and expired its original 20-second wait. The preserved log is `qa/results/business-initial-network-failure.log`; this was not reclassified as PASS or hidden by widening the timeout.

## Client correction

In PairingService, receiving a different remote hello previously regenerated the local ephemeral key/hello as well. The opposite client could do the same, producing different consent transcripts during reconnect. The local signed hello now stays stable for its own connection while peer handshake state is cleared. A real peer-disconnect transition rotates the hello once, so future sessions use fresh transcript/key material. Duplicate absence/status events do not continuously re-key.

Known paired identities may ignore an authentic consent for a different session; it cannot set remote approval, bind a new peer, or start sync. Invalid signatures/device IDs still fail, first pairing still requires both confirmations for the current transcript, and AEAD/session/counter validation remains strict. Pinned keys, route IDs, space IDs and Operation Log payloads are unchanged. No server deployment or wire-format migration was introduced.

A live/connecting WebSocket or an ongoing route request is not interrupted by the path monitor's initial callback. Cancellation of an old queued sender cannot fail the new session. Test fixtures explicitly suppress automatic restore, even if a copied store contains a real RelayBinding.

## Verification boundary

The real WebSocket integration case now exercises its original reconnect and three additional one-sided reconnect rounds, checking snapshot convergence, task preservation, no new pairing prompt, unchanged space and peer public keys. Its timeout is unchanged. Integration cases run serially to respect the shared source-IP limits; production rate limits remain enabled. QA starts an owner-only temporary local Worker state on a dedicated ephemeral port rather than reusing a user's development service.

Build 3 public Relay tests also ran from this Mac: two cases passed, including V2-to-V3 saved-route upgrade, finance/media acknowledgement and repeated reconnect. This is a one-Mac public service integration check, not physical dual-Mac/different-Wi-Fi acceptance or an independent protocol security review.
