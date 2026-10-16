import { exports } from "cloudflare:workers";
import { describe, it, expect } from "vitest";
import {
  canonical,
  sha,
  stableId,
  verifyArchive,
  type AuthorizationArchive,
  type SignedAuthorization,
} from "../src/multidevice";
const encoder = new TextEncoder(),
  b64 = (b: Uint8Array) => btoa(String.fromCharCode(...b));
async function device(userId = crypto.randomUUID().toUpperCase()) {
  const key = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  return {
    key,
    descriptor: {
      deviceId: crypto.randomUUID().toUpperCase(),
      userId,
      initialSpaceId: crypto.randomUUID().toUpperCase(),
      publicKey: b64(
        new Uint8Array(await crypto.subtle.exportKey("raw", key.publicKey)),
      ),
      displayName: "Synthetic device",
      protocolVersion: 3,
      initialTimeZoneIdentifier: "Asia/Shanghai",
    },
  };
}
type Device = Awaited<ReturnType<typeof device>>;
async function sign(d: Device, body: unknown) {
  return b64(
    new Uint8Array(
      await crypto.subtle.sign(
        "Ed25519",
        d.key.privateKey,
        encoder.encode(canonical(body)),
      ),
    ),
  );
}
async function request(
  d: Device,
  method: string,
  path: string,
  body: unknown = {},
) {
  const headers = { "CF-Connecting-IP": d.descriptor.deviceId },
    challenge = (await (
      await exports.default.fetch(
        "https://service.test" +
          (path.startsWith("/v2/") ? "/v2/challenge" : "/v1/challenge"),
        {
          headers,
        },
      )
    ).json()) as any;
  const text = method === "GET" ? "" : JSON.stringify(body),
    digest = Array.from(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", encoder.encode(text)),
      ),
    )
      .map((x) => x.toString(16).padStart(2, "0"))
      .join("");
  const proof = [
      "Together-Auth-1",
      challenge.nonce,
      method,
      path,
      digest,
      d.descriptor.deviceId,
    ].join("\n"),
    signature = b64(
      new Uint8Array(
        await crypto.subtle.sign(
          "Ed25519",
          d.key.privateKey,
          encoder.encode(proof),
        ),
      ),
    );
  return exports.default.fetch("https://service.test" + path, {
    method,
    body: method === "GET" ? undefined : text,
    headers: {
      ...headers,
      "X-Together-Challenge": challenge.id,
      "X-Together-Device": d.descriptor.deviceId,
      "X-Together-Key": d.descriptor.publicKey,
      "X-Together-Signature": signature,
    },
  });
}
async function fixture() {
  const a = await device(),
    b = await device(),
    body = (d: Device) => ({
      descriptor: d.descriptor,
      profileName: "Synthetic fixture",
    });
  const invite = (await (
    await request(a, "POST", "/v1/invitations", body(a))
  ).json()) as any;
  expect(
    (
      await request(b, "POST", "/v1/invitations/join", {
        ...body(b),
        code: invite.code,
      })
    ).status,
  ).toBe(200);
  for (const d of [a, b])
    expect(
      (
        await request(d, "POST", `/v1/routes/${invite.routeId}/confirm`, {
          transcript: "a".repeat(64),
        })
      ).status,
    ).toBe(200);
  const roots = [a, b].sort((x, y) =>
      x.descriptor.deviceId < y.descriptor.deviceId ? -1 : 1,
    ),
    spaceId = await stableId(
      "space:" + roots.map((d) => d.descriptor.deviceId).join(":"),
    );
  const genesisBody = {
    version: 4,
    spaceId,
    memberIds: [a.descriptor.userId, b.descriptor.userId].sort(),
    roots: roots.map((d) => d.descriptor),
    legacySpaceIds: [
      ...new Set([
        spaceId,
        a.descriptor.initialSpaceId,
        b.descriptor.initialSpaceId,
      ]),
    ].sort(),
    sharedTimeZoneIdentifier: "Asia/Shanghai",
    legacyCheckpoint: {
      count: 0,
      digest: Array.from(
        new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            encoder.encode("Together-Inventory-4\n"),
          ),
        ),
      )
        .map((x) => x.toString(16).padStart(2, "0"))
        .join(""),
    },
  };
  const authorization: AuthorizationArchive = {
    genesis: {
      body: genesisBody,
      signatures: await Promise.all(
        roots.map(async (d) => ({
          deviceId: d.descriptor.deviceId,
          signature: await sign(d, genesisBody),
        })),
      ),
    },
    events: [],
  };
  const response = await request(a, "POST", "/v2/spaces", {
    legacyRouteId: invite.routeId,
    authorization,
  });
  expect(response.status).toBe(200);
  return { a, b, spaceId, authorization, legacyRouteId: invite.routeId };
}
async function grant(
  owner: Device,
  added: Device,
  archive: AuthorizationArchive,
): Promise<SignedAuthorization> {
  const previous = archive.events
    .filter((e) => e.body.ownerId === owner.descriptor.userId)
    .at(-1);
  const body = {
    version: 4,
    spaceId: archive.genesis.body.spaceId,
    ownerId: owner.descriptor.userId,
    revision: previous ? previous.body.revision + 1 : 1,
    previousDigest: await sha(previous ?? archive.genesis),
    authorizerDeviceId: owner.descriptor.deviceId,
    action: "grant" as const,
    device: added.descriptor,
    epochId: crypto.randomUUID().toUpperCase(),
  };
  return { body, signature: await sign(owner, body) };
}
async function enroll(
  f: Awaited<ReturnType<typeof fixture>>,
  owner: Device,
  d: Device,
) {
  const event = await grant(owner, d, f.authorization),
    response = await request(owner, "POST", `/v2/spaces/${f.spaceId}/devices`, {
      event,
    });
  expect(response.status).toBe(200);
  f.authorization = ((await response.json()) as any).archive;
  return event;
}
async function socket(d: Device, spaceId: string) {
  const response = await request(d, "POST", `/v2/spaces/${spaceId}/ticket`);
  expect(response.status).toBe(200);
  const ticket = (await response.json()) as any;
  const opened = await exports.default.fetch(
    `https://service.test/v2/socket/${spaceId}`,
    {
      headers: {
        Upgrade: "websocket",
        Authorization: "Bearer " + ticket.ticket,
      },
    },
  );
  expect(opened.status).toBe(101);
  const ws = opened.webSocket!;
  ws.accept();
  return { ws, ticket };
}
function message(ws: WebSocket, predicate: (v: any) => boolean): Promise<any> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      ws.removeEventListener("message", handler);
      reject(Error("No expected routed frame"));
    }, 2000);
    function handler(e: MessageEvent) {
      const value = JSON.parse(String(e.data));
      if (predicate(value)) {
        clearTimeout(timeout);
        ws.removeEventListener("message", handler);
        resolve(value);
      }
    }
    ws.addEventListener("message", handler);
  });
}
function closed(ws: WebSocket) {
  return new Promise<number>((resolve) =>
    ws.addEventListener("close", (e) => resolve(e.code), { once: true }),
  );
}
describe("additive multi-device relay / real Durable Objects", () => {
  it("preserves original pins, space and route on repeated bootstrap", async () => {
    const f = await fixture(),
      legacy = (await (
        await request(f.a, "GET", `/v1/routes/${f.legacyRouteId}`)
      ).json()) as any;
    expect(legacy.paired).toBe(true);
    const child = await device(f.a.descriptor.userId);
    await enroll(f, f.a, child);
    expect(
      (await request(child, "GET", `/v2/spaces/${f.spaceId}`)).status,
    ).toBe(200);
    const repeated = (await (
      await request(f.a, "POST", "/v2/spaces", {
        legacyRouteId: f.legacyRouteId,
        authorization: { ...f.authorization, events: [] },
      })
    ).json()) as any;
    expect(repeated.devices).toHaveLength(3);
    const attacker = await device(f.a.descriptor.userId);
    expect(
      (await request(attacker, "GET", `/v2/spaces/${f.spaceId}`)).status,
    ).toBe(403);
  });
  it("rejects forged grants, owner substitution and competing authorization branches", async () => {
    const f = await fixture(),
      child = await device(f.a.descriptor.userId),
      event = await grant(f.a, child, f.authorization),
      path = `/v2/spaces/${f.spaceId}/devices`;
    expect(
      (
        await request(f.a, "POST", path, {
          event: { ...event, signature: await sign(f.b, event.body) },
        })
      ).status,
    ).toBe(403);
    expect((await request(f.b, "POST", path, { event })).status).toBe(403);
    expect((await request(f.a, "POST", path, { event })).status).toBe(200);
    expect((await request(f.a, "POST", path, { event })).status).toBe(200);
    const competitor = await grant(
      f.a,
      await device(f.a.descriptor.userId),
      f.authorization,
    );
    expect(
      (await request(f.a, "POST", path, { event: competitor })).status,
    ).toBe(409);
  });
  it("retains four sockets and routes only to the explicit recipient", async () => {
    const f = await fixture(),
      a2 = await device(f.a.descriptor.userId),
      b2 = await device(f.b.descriptor.userId);
    await enroll(f, f.a, a2);
    await enroll(f, f.b, b2);
    const sockets = await Promise.all(
      [f.a, a2, f.b, b2].map((d) => socket(d, f.spaceId)),
    );
    try {
      const received = message(sockets[3].ws, (v) => v.kind === "relay4"),
        frame = {
          kind: "relay4",
          senderDeviceId: a2.descriptor.deviceId,
          recipientDeviceId: b2.descriptor.deviceId,
          packet: { kind: "encrypted", ciphertext: "synthetic ciphertext" },
        };
      sockets[1].ws.send(JSON.stringify(frame));
      expect(await received).toEqual(frame);
      for (const s of sockets) expect(s.ws.readyState).toBe(WebSocket.OPEN);
      expect(
        (await verifyArchive(f.authorization)).devices.filter(
          (d) => !d.revokedAt,
        ),
      ).toHaveLength(4);
    } finally {
      for (const s of sockets) s.ws.close();
    }
  });
  it("rejects sender spoofing and a consumed 60-second ticket", async () => {
    const f = await fixture(),
      a = await socket(f.a, f.spaceId),
      b = await socket(f.b, f.spaceId);
    try {
      expect(
        (
          await exports.default.fetch(
            `https://service.test/v2/socket/${f.spaceId}`,
            {
              headers: {
                Upgrade: "websocket",
                Authorization: "Bearer " + a.ticket.ticket,
              },
            },
          )
        ).status,
      ).toBe(401);
      expect(a.ticket.expiresAt - Date.now()).toBeLessThanOrEqual(60000);
      const close = closed(a.ws);
      a.ws.send(
        JSON.stringify({
          kind: "relay4",
          senderDeviceId: f.b.descriptor.deviceId,
          recipientDeviceId: f.a.descriptor.deviceId,
          packet: { kind: "hello" },
        }),
      );
      expect(await close).toBe(1008);
    } finally {
      a.ws.close();
      b.ws.close();
    }
  });
  it("revokes future access, retains keys and rejects pre-revocation tickets", async () => {
    const f = await fixture(),
      d = await device(f.a.descriptor.userId),
      added = await enroll(f, f.a, d),
      ticket = (await (
        await request(d, "POST", `/v2/spaces/${f.spaceId}/ticket`)
      ).json()) as any;
    const body = {
      ...added.body,
      revision: 2,
      previousDigest: await sha(added),
      action: "revoke" as const,
      cutoff: { sequence: 0, digest: "0".repeat(64) },
    };
    const response = await request(
      f.a,
      "POST",
      `/v2/spaces/${f.spaceId}/devices`,
      { event: { body, signature: await sign(f.a, body) } },
    );
    expect(response.status).toBe(200);
    expect(
      ((await response.json()) as any).devices.find(
        (v: any) => v.descriptor.deviceId === d.descriptor.deviceId,
      ).descriptor.publicKey,
    ).toBe(d.descriptor.publicKey);
    expect(
      (await request(d, "POST", `/v2/spaces/${f.spaceId}/ticket`)).status,
    ).toBe(403);
    expect(
      (
        await exports.default.fetch(
          `https://service.test/v2/socket/${f.spaceId}`,
          {
            headers: {
              Upgrade: "websocket",
              Authorization: "Bearer " + ticket.ticket,
            },
          },
        )
      ).status,
    ).toBe(403);
  });
  it("does not persist operation or media frames in routing metadata", async () => {
    const f = await fixture(),
      a = await socket(f.a, f.spaceId),
      b = await socket(f.b, f.spaceId);
    try {
      const received = message(b.ws, (v) => v.kind === "relay4");
      a.ws.send(
        JSON.stringify({
          kind: "relay4",
          senderDeviceId: f.a.descriptor.deviceId,
          recipientDeviceId: f.b.descriptor.deviceId,
          packet: { kind: "encrypted", ciphertext: "not stored" },
        }),
      );
      await received;
      const state = await (
        await request(f.a, "GET", `/v2/spaces/${f.spaceId}`)
      ).text();
      expect(state).not.toContain("not stored");
      expect(state).not.toContain("ciphertext");
    } finally {
      a.ws.close();
      b.ws.close();
    }
  });
});
