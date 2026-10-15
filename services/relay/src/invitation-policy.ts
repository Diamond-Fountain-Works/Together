export const INVITATION_TTL_MS = 28_800_000;
export function invitationExpired(expiresAt: number, now = Date.now()): boolean {
  return expiresAt <= now;
}
