// Public authorization metadata only. No operation/media plaintext is stored.
export type MDDescriptor = {
  deviceId: string;
  userId: string;
  initialSpaceId: string;
  publicKey: string;
  displayName: string;
  protocolVersion: number;
  initialTimeZoneIdentifier?: string;
};
export type Frontier = { sequence: number; digest: string };
export type GenesisBody = {
  version: number;
  spaceId: string;
  memberIds: string[];
  roots: MDDescriptor[];
  legacySpaceIds: string[];
  sharedTimeZoneIdentifier: string;
  legacyCheckpoint: { count: number; digest: string };
};
export type SignedGenesis = {
  body: GenesisBody;
  signatures: { deviceId: string; signature: string }[];
};
export type AuthorizationBody = {
  version: number;
  spaceId: string;
  ownerId: string;
  revision: number;
  previousDigest: string;
  authorizerDeviceId: string;
  action: "grant" | "revoke";
  device: MDDescriptor;
  epochId: string;
  cutoff?: Frontier;
};
export type SignedAuthorization = {
  body: AuthorizationBody;
  signature: string;
};
export type AuthorizationArchive = {
  genesis: SignedGenesis;
  events: SignedAuthorization[];
};
export type MDDevice = {
  descriptor: MDDescriptor;
  epochId: string;
  revokedAt?: Frontier;
};
export type MDState = {
  schemaVersion: 2;
  legacyRouteId: string;
  spaceId: string;
  archive: AuthorizationArchive;
  devices: MDDevice[];
  authorizationDigest: string;
};
export class MultideviceError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}
const uuid = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;
const digest = /^[0-9a-f]{64}$/;
const encoder = new TextEncoder();
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value !== null && typeof value === "object")
    return (
      "{" +
      Object.keys(value)
        .sort()
        .map((k) => JSON.stringify(k) + ":" + canonical((value as any)[k]))
        .join(",") +
      "}"
    );
  if (typeof value === "number" && !Number.isSafeInteger(value))
    throw new MultideviceError(400, "INVALID_NUMBER");
  if (value === undefined) throw new MultideviceError(400, "INVALID_METADATA");
  return JSON.stringify(value);
}
export async function sha(value: unknown): Promise<string> {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(canonical(value))),
    ),
  )
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
function bytes(text: string, length: number): Uint8Array<ArrayBuffer> {
  try {
    const result = Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
    if (
      result.length !== length ||
      btoa(String.fromCharCode(...result)) !== text
    )
      throw Error();
    return result;
  } catch {
    throw new MultideviceError(400, "INVALID_ENCODING");
  }
}
function exact(value: any, required: string[], optional: string[] = []): void {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    required.some((k) => !Object.hasOwn(value, k)) ||
    Object.keys(value).some(
      (k) => !required.includes(k) && !optional.includes(k),
    )
  )
    throw new MultideviceError(400, "INVALID_METADATA");
}
function descriptor(d: MDDescriptor): void {
  exact(
    d,
    [
      "deviceId",
      "userId",
      "initialSpaceId",
      "publicKey",
      "displayName",
      "protocolVersion",
    ],
    ["initialTimeZoneIdentifier"],
  );
  if (
    !uuid.test(d.deviceId) ||
    !uuid.test(d.userId) ||
    !uuid.test(d.initialSpaceId) ||
    ![2, 3, 4].includes(d.protocolVersion) ||
    typeof d.displayName !== "string" ||
    d.displayName.length > 80
  )
    throw new MultideviceError(400, "INVALID_DEVICE");
  bytes(d.publicKey, 32);
  if (d.initialTimeZoneIdentifier !== undefined)
    zone(d.initialTimeZoneIdentifier);
}
function zone(value: string) {
  try {
    if (typeof value !== "string" || value.length > 128) throw Error();
    new Intl.DateTimeFormat("en", { timeZone: value });
  } catch {
    throw new MultideviceError(400, "INVALID_TIME_ZONE");
  }
}
async function verify(
  body: unknown,
  signature: string,
  key: string,
): Promise<void> {
  const publicKey = await crypto.subtle.importKey(
    "raw",
    bytes(key, 32),
    { name: "Ed25519" },
    false,
    ["verify"],
  );
  if (
    !(await crypto.subtle.verify(
      { name: "Ed25519" },
      publicKey,
      bytes(signature, 64),
      encoder.encode(canonical(body)),
    ))
  )
    throw new MultideviceError(403, "INVALID_AUTHORIZATION_SIGNATURE");
}
export async function stableId(seed: string): Promise<string> {
  const b = new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(seed)),
  ).slice(0, 16);
  b[6] = (b[6] & 15) | 80;
  b[8] = (b[8] & 63) | 128;
  const h = Array.from(b)
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
  return [
    h.slice(0, 8),
    h.slice(8, 12),
    h.slice(12, 16),
    h.slice(16, 20),
    h.slice(20),
  ].join("-");
}
function ordered(ids: string[]): boolean {
  return (
    new Set(ids).size === ids.length &&
    ids.every((id, i) => uuid.test(id) && (i === 0 || ids[i - 1] < id))
  );
}
export async function verifyArchive(
  archive: AuthorizationArchive,
): Promise<{ devices: MDDevice[]; authorizationDigest: string }> {
  exact(archive, ["genesis", "events"]);
  exact(archive.genesis, ["body", "signatures"]);
  const g = archive.genesis,
    b = g.body;
  exact(b, [
    "version",
    "spaceId",
    "memberIds",
    "roots",
    "legacySpaceIds",
    "sharedTimeZoneIdentifier",
    "legacyCheckpoint",
  ]);
  exact(b.legacyCheckpoint, ["count", "digest"]);
  if (
    b.version !== 4 ||
    !uuid.test(b.spaceId) ||
    !Array.isArray(b.memberIds) ||
    b.memberIds.length !== 2 ||
    !ordered(b.memberIds) ||
    !Array.isArray(b.roots) ||
    b.roots.length !== 2 ||
    !ordered(b.roots.map((d) => d.deviceId)) ||
    !Array.isArray(g.signatures) ||
    g.signatures.length !== 2 ||
    !ordered(g.signatures.map((s) => s.deviceId)) ||
    !ordered(b.legacySpaceIds) ||
    b.legacySpaceIds.length > 3 ||
    !b.legacySpaceIds.includes(b.spaceId) ||
    !Number.isSafeInteger(b.legacyCheckpoint.count) ||
    b.legacyCheckpoint.count < 0 ||
    !digest.test(b.legacyCheckpoint.digest) ||
    !Array.isArray(archive.events)
  )
    throw new MultideviceError(400, "INVALID_GENESIS");
  zone(b.sharedTimeZoneIdentifier);
  const genesisHash = await sha(g),
    devices: MDDevice[] = [],
    heads = new Map<string, { revision: number; digest: string }>();
  for (const root of b.roots) {
    descriptor(root);
    const proof = g.signatures.find((s) => s.deviceId === root.deviceId);
    if (!proof) throw new MultideviceError(403, "MISSING_ROOT_SIGNATURE");
    exact(proof, ["deviceId", "signature"]);
    await verify(b, proof.signature, root.publicKey);
    devices.push({
      descriptor: root,
      epochId: await stableId(
        `Together-Device-Epoch-4:${b.spaceId}:${root.deviceId}`,
      ),
    });
    heads.set(root.userId, { revision: 0, digest: genesisHash });
  }
  if (
    new Set(b.roots.map((d) => d.userId)).size !== 2 ||
    !b.roots.every((d) => b.memberIds.includes(d.userId)) ||
    new Set(b.roots.map((d) => d.publicKey)).size !== 2
  )
    throw new MultideviceError(403, "INVALID_MEMBERS");
  for (const event of archive.events) {
    exact(event, ["body", "signature"]);
    const e = event.body;
    exact(
      e,
      [
        "version",
        "spaceId",
        "ownerId",
        "revision",
        "previousDigest",
        "authorizerDeviceId",
        "action",
        "device",
        "epochId",
      ],
      ["cutoff"],
    );
    descriptor(e.device);
    const root = b.roots.find((d) => d.userId === e.ownerId),
      head = heads.get(e.ownerId);
    if (
      e.version !== 4 ||
      e.spaceId !== b.spaceId ||
      !root ||
      e.device.userId !== e.ownerId ||
      e.authorizerDeviceId !== root.deviceId ||
      !uuid.test(e.epochId)
    )
      throw new MultideviceError(403, "UNAUTHORIZED_DEVICE_GRANT");
    await verify(e, event.signature, root.publicKey);
    if (
      !head ||
      e.revision !== head.revision + 1 ||
      e.previousDigest !== head.digest
    )
      throw new MultideviceError(409, "AUTHORIZATION_FORK");
    const prior = devices.find(
      (d) => d.descriptor.deviceId === e.device.deviceId,
    );
    if (e.action === "grant") {
      if (
        prior ||
        e.cutoff !== undefined ||
        devices.filter((d) => !d.revokedAt).length >= 32 ||
        devices.some(
          (d) =>
            d.descriptor.publicKey === e.device.publicKey ||
            d.epochId === e.epochId,
        ) ||
        !e.device.initialTimeZoneIdentifier
      )
        throw new MultideviceError(403, "INVALID_DEVICE_GRANT");
      devices.push({ descriptor: e.device, epochId: e.epochId });
    } else if (e.action === "revoke") {
      if (
        !prior ||
        prior.revokedAt ||
        prior.epochId !== e.epochId ||
        canonical(prior.descriptor) !== canonical(e.device) ||
        e.device.deviceId === root.deviceId ||
        !e.cutoff
      )
        throw new MultideviceError(403, "INVALID_DEVICE_REVOCATION");
      exact(e.cutoff, ["sequence", "digest"]);
      if (
        !Number.isSafeInteger(e.cutoff.sequence) ||
        e.cutoff.sequence < 0 ||
        e.cutoff.sequence >= 9_000_000_000_000_000 ||
        !digest.test(e.cutoff.digest) ||
        (e.cutoff.sequence === 0 && e.cutoff.digest !== "0".repeat(64))
      )
        throw new MultideviceError(400, "INVALID_REVOCATION_FRONTIER");
      prior.revokedAt = e.cutoff;
    } else throw new MultideviceError(400, "INVALID_AUTHORIZATION_ACTION");
    heads.set(e.ownerId, { revision: e.revision, digest: await sha(event) });
  }
  // Independent owner streams can arrive in a different interleaving. The
  // handshake digest uses one canonical stream order on every platform.
  const normalized = {
    genesis: g,
    events: [...archive.events].sort((x, y) =>
      x.body.ownerId === y.body.ownerId
        ? x.body.revision - y.body.revision
        : x.body.ownerId < y.body.ownerId
          ? -1
          : 1,
    ),
  };
  return { devices, authorizationDigest: await sha(normalized) };
}
export function authorizedDevice(
  state: MDState,
  auth: { device: string; key: string },
): MDDevice {
  const value = state.devices.find(
    (d) =>
      d.descriptor.deviceId === auth.device &&
      d.descriptor.publicKey === auth.key &&
      !d.revokedAt,
  );
  if (!value) throw new MultideviceError(403, "NOT_AN_AUTHORIZED_DEVICE");
  return value;
}
