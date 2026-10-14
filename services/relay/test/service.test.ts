import { exports, env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { describe, it, expect } from "vitest";
const encode = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const sha = async (text: string) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", encode.encode(text))),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
async function device(name = "Fixture A", protocolVersion = 2) {
  const key = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  return {
    key,
    profileName: name,
    descriptor: {
      deviceId: crypto.randomUUID().toUpperCase(),
      userId: crypto.randomUUID().toUpperCase(),
      initialSpaceId: crypto.randomUUID().toUpperCase(),
      publicKey: b64(
        new Uint8Array(await crypto.subtle.exportKey("raw", key.publicKey)),
      ),
      displayName: name,
      protocolVersion,
      initialTimeZoneIdentifier: "Asia/Shanghai",
    },
  };
}
async function request(
  d: Awaited<ReturnType<typeof device>>,
  method: string,
  path: string,
  body: any = {},
  ip = "127.0.0.1",
) {
  const nonce = (await (
    await exports.default.fetch("https://service.test/v1/challenge", {
      headers: { "CF-Connecting-IP": ip },
    })
  ).json()) as any;
  const text = method === "GET" ? "" : JSON.stringify(body),
    message = [
      "Together-Auth-1",
      nonce.nonce,
      method,
      path,
      await sha(text),
      d.descriptor.deviceId,
    ].join("\n");
  const signature = b64(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "Ed25519" },
        d.key.privateKey,
        encode.encode(message),
      ),
    ),
  );
  return exports.default.fetch("https://service.test" + path, {
    method,
    body: method === "GET" ? undefined : text,
    headers: {
      "CF-Connecting-IP": ip,
      "X-Together-Challenge": nonce.id,
      "X-Together-Key": d.descriptor.publicKey,
      "X-Together-Device": d.descriptor.deviceId,
      "X-Together-Signature": signature,
    },
  });
}
const body = (d: Awaited<ReturnType<typeof device>>) => ({
  descriptor: d.descriptor,
  profileName: d.profileName,
});
describe("real Workers runtime / invitation and authorization", () => {
  it("accepts finance protocol 3 and keeps protocol 2 routes compatible", async () => {
    for (const version of [2, 3]) {
      const d = await device("Version fixture", version);
      const response = await request(d, "POST", "/v1/invitations", body(d), "version-" + version);
      expect(response.status).toBe(200);
    }
    const future = await device("Unsupported version", 99);
    expect((await request(future, "POST", "/v1/invitations", body(future), "unsupported-version")).status).toBe(400);
  });
  it("health declares realtime-only", async () => {
    const r = await exports.default.fetch("https://service.test/health");
    const status = (await r.json()) as any;
    expect(status.delivery).toBe("realtime-only");
    expect(status.deviceProtocols).toEqual([2, 3]);
  });
  it("creates unpredictable 12-character invitation, consumes once, requires both confirmations", async () => {
    const a = await device(),
      b = await device("Fixture B");
    const create = await request(a, "POST", "/v1/invitations", body(a), "a");
    expect(create.status).toBe(200);
    const invite = (await create.json()) as any;
    expect(/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}$/.test(invite.code)).toBe(
      true,
    );
    const joined = await request(
      b,
      "POST",
      "/v1/invitations/join",
      { ...body(b), code: invite.code },
      "b",
    );
    expect(joined.status).toBe(200);
    expect(((await joined.json()) as any).paired).toBe(false);
    expect(
      (
        await request(
          b,
          "POST",
          "/v1/invitations/join",
          { ...body(b), code: invite.code },
          "b",
        )
      ).status,
    ).toBe(400);
    const transcript = "a".repeat(64),
      path = "/v1/routes/" + invite.routeId + "/confirm";
    expect(
      (
        (await (
          await request(a, "POST", path, { transcript }, "a")
        ).json()) as any
      ).paired,
    ).toBe(false);
    expect(
      (
        (await (
          await request(b, "POST", path, { transcript }, "b")
        ).json()) as any
      ).paired,
    ).toBe(true);
    const outsider = await device("Fixture C");
    expect(
      (await request(outsider, "GET", "/v1/routes/" + invite.routeId, {}, "c"))
        .status,
    ).toBe(403);
  });
  it("expired invitation is rejected", async () => {
    const a = await device(),
      b = await device();
    const invite = (await (
      await request(a, "POST", "/v1/invitations", body(a), "expired-a")
    ).json()) as any;
    const key = "invite:" + (await sha(invite.code)),
      stub = env.DIRECTORY.get(env.DIRECTORY.idFromName("directory-v1"));
    await runInDurableObject(stub, async (_: any, state: any) => {
      const row = await state.storage.get(key);
      row.expiresAt = 0;
      await state.storage.put(key, row);
    });
    expect(
      (
        await request(
          b,
          "POST",
          "/v1/invitations/join",
          { ...body(b), code: invite.code },
          "expired-b",
        )
      ).status,
    ).toBe(400);
  });
  it("migration rejects a device with a different pin without consuming the valid invitation", async () => {
    const a = await device(),
      old = await device("Old partner"),
      outsider = await device();
    const invite = (await (
      await request(
        a,
        "POST",
        "/v1/invitations",
        { ...body(a), expectedPeer: old.descriptor },
        "migration-a",
      )
    ).json()) as any;
    expect(
      (
        await request(
          outsider,
          "POST",
          "/v1/invitations/join",
          { ...body(outsider), code: invite.code },
          "migration-c",
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await request(
          old,
          "POST",
          "/v1/invitations/join",
          { ...body(old), code: invite.code },
          "migration-b",
        )
      ).status,
    ).toBe(200);
  });
  it("wrong attempts hit rate limits", async () => {
    const d = await device();
    let limited = false;
    for (let i = 0; i < 12; i++) {
      const response = await request(
        d,
        "POST",
        "/v1/invitations/join",
        { ...body(d), code: "ZZZZZZZZZZZZ" },
        "rate-test",
      );
      if (response.status === 429) limited = true;
    }
    expect(limited).toBe(true);
  });
  it("forged HTTP identity cannot create an invitation", async () => {
    const a = await device(),
      b = await device();
    expect(
      (await request(a, "POST", "/v1/invitations", body(b), "forge")).status,
    ).toBe(403);
  });
  it("WebSocket requires a fresh scoped ticket and does not forward encrypted payload before confirmation", async () => {
    const a = await device(),
      b = await device();
    const invite = (await (
      await request(a, "POST", "/v1/invitations", body(a), "socket-a")
    ).json()) as any;
    await request(
      b,
      "POST",
      "/v1/invitations/join",
      { ...body(b), code: invite.code },
      "socket-b",
    );
    const ticket = (await (
      await request(
        a,
        "POST",
        "/v1/routes/" + invite.routeId + "/ticket",
        {},
        "socket-a",
      )
    ).json()) as any;
    const response = await exports.default.fetch(
      "https://service.test/v1/socket/" + invite.routeId,
      {
        headers: {
          Upgrade: "websocket",
          Authorization: "Bearer " + ticket.ticket,
        },
      },
    );
    expect(response.status).toBe(101);
    const socket = response.webSocket!;
    socket.accept();
    const closed = new Promise<number>((resolve) =>
      socket.addEventListener("close", (event) => resolve(event.code)),
    );
    socket.send(JSON.stringify({ kind: "encrypted", ciphertext: "AA==" }));
    expect(await closed).toBe(1008);
    expect(
      (
        await exports.default.fetch(
          "https://service.test/v1/socket/" + invite.routeId,
          {
            headers: {
              Upgrade: "websocket",
              Authorization: "Bearer " + ticket.ticket,
            },
          },
        )
      ).status,
    ).toBe(401);
  });
});
