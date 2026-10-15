# Invitation eight-hour local acceptance

Branch `fix/invitation-eight-hours`, based on Monorepo `1832df0`. Separate from multi-device protocol work and PR #2 human visual acceptance.

- Server expiry uses exactly 28,800,000 ms. Expired means server `now >= expiresAt`; successful join is consumed in one Durable Object transaction.
- Two new tests cover the exact boundary / issued server deadline and two concurrent joining devices (one 200, one 400). Existing forged identity, different migration pin, reuse/expiry/rate and WebSocket tests remain enabled.
- Actual `npm run check`: PASS. Actual `npm test`: 10 PASS / 0 FAIL. Nonce/ticket code remains 60,000 ms; the concurrent-join test also checks the actual issued ticket deadline.
- Client source inspection: ConnectionView displays `PairingService.invitationExpiresAt` from the actual RelayInvitation expiresAt. There is no static ten-minute promise to replace. An old deployed server continues to show its real deadline.
- App/core source, signed JSON, local store schema, identities and saved routes are unchanged. No new macOS binary or baseline images were produced.
- Production deployment, live eight-hour behavior and physical two-Mac tests: NOT RUN. Production remains the previously audited 10-minute implementation. Issue #1 must remain open until deployment and verification are authorized/completed.
- Rollback: revert the isolated source PR; keep existing paired routes. No database deletion, re-pairing or Durable Object recreation is needed. Already issued invitations keep their stored expiresAt; changing the source constant does not extend them retroactively.
