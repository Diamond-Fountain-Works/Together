import { DurableObject } from "cloudflare:workers";
export interface Env {
  DIRECTORY: DurableObjectNamespace<ConnectionDirectory>;
  ROOMS: DurableObjectNamespace<RelayRoom>;
  MAX_FRAME_BYTES: string;
  SERVICE_VERSION: string;
}
type Descriptor = {
  deviceId: string;
  userId: string;
  initialSpaceId: string;
  publicKey: string;
  displayName: string;
  protocolVersion: number;
  initialTimeZoneIdentifier?: string;
};
type Member = { descriptor: Descriptor; profileName: string };
type Route = {
  routeId: string;
  members: Member[];
  expiresAt: number;
  paired: boolean;
  revoked: boolean;
  confirmed: string[];
  transcript?: string;
};
type Invitation = {
  owner: Member;
  expectedPeer?: Descriptor;
  routeId: string;
  expiresAt: number;
  used: boolean;
};
const encoder = new TextEncoder(),
  alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const uuid = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;
function randomBytes(n: number): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(n));
}
function b64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}
function from64(text: string): Uint8Array<ArrayBuffer> {
  try {
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  } catch {
    throw new ServiceError(400, "INVALID_ENCODING");
  }
}
async function hash(data: string | Uint8Array): Promise<string> {
  const bytes = typeof data === "string" ? encoder.encode(data) : data;
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes).buffer),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
function id(): string {
  return crypto.randomUUID().toUpperCase();
}
function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
class ServiceError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}
function checkDescriptor(d: Descriptor): void {
  if (
    !d ||
    !uuid.test(d.deviceId) ||
    !uuid.test(d.userId) ||
    !uuid.test(d.initialSpaceId) ||
    from64(d.publicKey).length !== 32 ||
    ![2, 3].includes(d.protocolVersion) ||
    typeof d.displayName !== "string" ||
    d.displayName.length > 80 ||
    !d.initialTimeZoneIdentifier
  )
    throw new ServiceError(400, "INVALID_DEVICE");
  try {
    new Intl.DateTimeFormat("en", { timeZone: d.initialTimeZoneIdentifier });
  } catch {
    throw new ServiceError(400, "INVALID_TIME_ZONE");
  }
}
function member(body: any, auth: { key: string; device: string }): Member {
  checkDescriptor(body.descriptor);
  if (
    body.descriptor.publicKey !== auth.key ||
    body.descriptor.deviceId !== auth.device ||
    typeof body.profileName !== "string" ||
    body.profileName.length > 80 ||
    !body.profileName.trim()
  )
    throw new ServiceError(403, "IDENTITY_MISMATCH");
  return { descriptor: body.descriptor, profileName: body.profileName };
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (new URL(request.url).pathname === "/health" && request.method === "GET")
      return json({
        status: "ok",
        protocol: 1,
        deviceProtocols: [2, 3],
        delivery: "realtime-only",
        version: env.SERVICE_VERSION,
      });
    if (Number(request.headers.get("Content-Length") ?? 0) > 16384)
      return json({ error: "REQUEST_TOO_LARGE" }, 413);
    try {
      return await env.DIRECTORY.get(
        env.DIRECTORY.idFromName("directory-v1"),
      ).fetch(request);
    } catch {
      return json({ error: "SERVICE_UNAVAILABLE" }, 503);
    }
  },
} satisfies ExportedHandler<Env>;

export class ConnectionDirectory extends DurableObject<Env> {
  private async rate(
    request: Request,
    scope: string,
    limit: number,
    windowMs = 60000,
  ): Promise<void> {
    const name =
        "rate:" +
        scope +
        ":" +
        (await hash(request.headers.get("CF-Connecting-IP") ?? "local")),
      now = Date.now();
    await this.ctx.storage.transaction(async (tx) => {
      let row = await tx.get<{ start: number; count: number }>(name);
      if (!row || now - row.start >= windowMs) row = { start: now, count: 0 };
      if (row.count >= limit) throw new ServiceError(429, "RATE_LIMITED");
      row.count++;
      await tx.put(name, row);
    });
  }
  private async authenticate(
    request: Request,
    bodyText: string,
  ): Promise<{ key: string; device: string }> {
    const challengeId = request.headers.get("X-Together-Challenge") ?? "",
      key = request.headers.get("X-Together-Key") ?? "",
      device = request.headers.get("X-Together-Device") ?? "",
      signature = from64(request.headers.get("X-Together-Signature") ?? "");
    if (
      !uuid.test(device) ||
      from64(key).length !== 32 ||
      signature.length !== 64
    )
      throw new ServiceError(401, "AUTH_REQUIRED");
    const challenge = await this.ctx.storage.transaction(async (tx) => {
      const nonce = await tx.get<{ nonce: string; expiresAt: number }>(
        "nonce:" + challengeId,
      );
      if (!nonce || nonce.expiresAt < Date.now())
        throw new ServiceError(401, "CHALLENGE_EXPIRED");
      await tx.delete("nonce:" + challengeId);
      return nonce;
    });
    const message = [
      "Together-Auth-1",
      challenge.nonce,
      request.method,
      new URL(request.url).pathname,
      await hash(bodyText),
      device,
    ].join("\n");
    const publicKey = await crypto.subtle.importKey(
      "raw",
      from64(key),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    if (
      !(await crypto.subtle.verify(
        { name: "Ed25519" },
        publicKey,
        signature,
        encoder.encode(message),
      ))
    )
      throw new ServiceError(401, "INVALID_SIGNATURE");
    return { key, device };
  }
  private async getRoute(
    routeId: string,
    auth: { key: string; device: string },
  ): Promise<Route> {
    const route = await this.ctx.storage.get<Route>("route:" + routeId);
    if (
      !route ||
      route.revoked ||
      (!route.paired && route.expiresAt < Date.now())
    )
      throw new ServiceError(404, "ROUTE_UNAVAILABLE");
    if (
      !route.members.some(
        (m) =>
          m.descriptor.deviceId === auth.device &&
          m.descriptor.publicKey === auth.key,
      )
    )
      throw new ServiceError(403, "NOT_A_MEMBER");
    return route;
  }
  async fetch(request: Request): Promise<Response> {
    try {
      const path = new URL(request.url).pathname;
      await this.rate(request, "requests", 120);
      if (path === "/v1/challenge" && request.method === "GET") {
        await this.rate(request, "challenge", 40);
        const challenge = {
          id: id(),
          nonce: b64(randomBytes(32)),
          expiresAt: Date.now() + 60000,
        };
        await this.ctx.storage.put("nonce:" + challenge.id, {
          nonce: challenge.nonce,
          expiresAt: challenge.expiresAt,
        });
        await this.ctx.storage.setAlarm(Date.now() + 600000);
        return json(challenge);
      }
      const socket = path.match(/^\/v1\/socket\/([0-9A-F-]+)$/);
      if (
        socket &&
        request.headers.get("Upgrade")?.toLowerCase() === "websocket"
      ) {
        const token =
            request.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "",
          key = "ticket:" + (await hash(token));
        const ticket = await this.ctx.storage.transaction(async (tx) => {
          const value = await tx.get<{
            routeId: string;
            device: string;
            key: string;
            expiresAt: number;
          }>(key);
          await tx.delete(key);
          return value;
        });
        if (
          !ticket ||
          ticket.routeId !== socket[1] ||
          ticket.expiresAt < Date.now()
        )
          throw new ServiceError(401, "TICKET_EXPIRED");
        const route = await this.getRoute(ticket.routeId, {
            device: ticket.device,
            key: ticket.key,
          }),
          room = this.env.ROOMS.get(this.env.ROOMS.idFromName(route.routeId));
        await room.configure(route);
        return await room.fetch(
          new Request("https://room.internal/socket", {
            headers: { Upgrade: "websocket", "X-Member": ticket.device },
          }),
        );
      }
      const bodyText = request.method === "GET" ? "" : await request.text();
      if (encoder.encode(bodyText).length > 16384)
        throw new ServiceError(413, "REQUEST_TOO_LARGE");
      const auth = await this.authenticate(request, bodyText),
        body = bodyText ? JSON.parse(bodyText) : {};
      if (path === "/v1/invitations" && request.method === "POST") {
        await this.rate(request, "create", 6, 600000);
        const owner = member(body, auth);
        if (body.expectedPeer) {
          checkDescriptor(body.expectedPeer);
          if (body.expectedPeer.deviceId === auth.device)
            throw new ServiceError(400, "SAME_DEVICE");
        }
        const code = Array.from(
            randomBytes(12),
            (b) => alphabet[b % alphabet.length],
          ).join(""),
          invitation: Invitation = {
            owner,
            expectedPeer: body.expectedPeer,
            routeId: id(),
            expiresAt: Date.now() + 600000,
            used: false,
          };
        await this.ctx.storage.put("invite:" + (await hash(code)), invitation);
        await this.ctx.storage.put("route:" + invitation.routeId, {
          routeId: invitation.routeId,
          members: [owner],
          expiresAt: invitation.expiresAt,
          paired: false,
          revoked: false,
          confirmed: [],
        } satisfies Route);
        await this.ctx.storage.setAlarm(Date.now() + 600000);
        return json({
          code,
          routeId: invitation.routeId,
          expiresAt: invitation.expiresAt,
        });
      }
      if (path === "/v1/invitations/join" && request.method === "POST") {
        await this.rate(request, "join", 10);
        const joining = member(body, auth),
          code = String(body.code ?? "")
            .trim()
            .toUpperCase()
            .replace(/[\s-]/g, "");
        if (!/^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{12}$/.test(code))
          throw new ServiceError(400, "INVITATION_UNAVAILABLE");
        const key = "invite:" + (await hash(code)),
          route = await this.ctx.storage.transaction(async (tx) => {
            const invitation = await tx.get<Invitation>(key);
            if (
              !invitation ||
              invitation.used ||
              invitation.expiresAt < Date.now()
            )
              throw new ServiceError(400, "INVITATION_UNAVAILABLE");
            if (
              invitation.owner.descriptor.deviceId ===
                joining.descriptor.deviceId ||
              invitation.owner.descriptor.userId === joining.descriptor.userId
            )
              throw new ServiceError(400, "SAME_DEVICE");
            if (
              invitation.expectedPeer &&
              (invitation.expectedPeer.deviceId !==
                joining.descriptor.deviceId ||
                invitation.expectedPeer.userId !== joining.descriptor.userId ||
                invitation.expectedPeer.publicKey !==
                  joining.descriptor.publicKey ||
                invitation.expectedPeer.initialSpaceId !==
                  joining.descriptor.initialSpaceId)
            )
              throw new ServiceError(403, "MIGRATION_IDENTITY_MISMATCH");
            invitation.used = true;
            await tx.put(key, invitation);
            const row: Route = {
              routeId: invitation.routeId,
              members: [invitation.owner, joining],
              expiresAt: invitation.expiresAt,
              paired: false,
              revoked: false,
              confirmed: [],
            };
            await tx.put("route:" + row.routeId, row);
            return row;
          });
        await this.env.ROOMS.get(
          this.env.ROOMS.idFromName(route.routeId),
        ).configure(route);
        return json(route);
      }
      const match = path.match(
        /^\/v1\/routes\/([0-9A-F-]+)(?:\/(ticket|confirm|revoke))?$/,
      );
      if (!match) throw new ServiceError(404, "NOT_FOUND");
      let route = await this.getRoute(match[1], auth);
      if (request.method === "GET" && !match[2]) return json(route);
      if (request.method !== "POST")
        throw new ServiceError(405, "METHOD_NOT_ALLOWED");
      if (match[2] === "ticket") {
        const ticket = b64(randomBytes(32));
        await this.ctx.storage.put("ticket:" + (await hash(ticket)), {
          routeId: route.routeId,
          device: auth.device,
          key: auth.key,
          expiresAt: Date.now() + 60000,
        });
        return json({
          ticket,
          routeId: route.routeId,
          expiresAt: Date.now() + 60000,
        });
      }
      if (match[2] === "confirm") {
        if (!/^[0-9a-f]{64}$/.test(body.transcript ?? ""))
          throw new ServiceError(400, "INVALID_TRANSCRIPT");
        route = await this.ctx.storage.transaction(async (tx) => {
          const row = (await tx.get<Route>("route:" + route.routeId))!;
          if (row.revoked || (!row.paired && row.expiresAt < Date.now()))
            throw new ServiceError(404, "ROUTE_UNAVAILABLE");
          if (!row.paired) {
            if (row.transcript !== body.transcript) {
              row.transcript = body.transcript;
              row.confirmed = [];
            }
            if (!row.confirmed.includes(auth.device))
              row.confirmed.push(auth.device);
            row.paired = row.members.length === 2 && row.confirmed.length === 2;
            await tx.put("route:" + row.routeId, row);
          }
          return row;
        });
        await this.env.ROOMS.get(
          this.env.ROOMS.idFromName(route.routeId),
        ).configure(route);
        return json(route);
      }
      if (match[2] === "revoke") {
        route.revoked = true;
        await this.ctx.storage.put("route:" + route.routeId, route);
        await this.env.ROOMS.get(
          this.env.ROOMS.idFromName(route.routeId),
        ).configure(route);
        return json({ revoked: true });
      }
      throw new ServiceError(404, "NOT_FOUND");
    } catch (error) {
      if (error instanceof ServiceError)
        return json({ error: error.code }, error.status);
      return json({ error: "INVALID_REQUEST" }, 400);
    }
  }
  async alarm(): Promise<void> {
    const now = Date.now(),
      entries = await this.ctx.storage.list<any>();
    for (const [key, value] of entries) {
      if (
        (key.startsWith("nonce:") ||
          key.startsWith("ticket:") ||
          key.startsWith("invite:") ||
          (key.startsWith("route:") && !value.paired)) &&
        value.expiresAt < now
      )
        await this.ctx.storage.delete(key);
      if (key.startsWith("rate:") && now - value.start > 600000)
        await this.ctx.storage.delete(key);
    }
    await this.ctx.storage.setAlarm(now + 600000);
  }
}

export class RelayRoom extends DurableObject<Env> {
  async configure(route: Route): Promise<void> {
    await this.ctx.storage.put("route", route);
    if (route.revoked) {
      for (const s of this.ctx.getWebSockets()) s.close(4003, "Route revoked");
      return;
    }
    this.status(route);
  }
  private status(route: Route): void {
    const message = JSON.stringify({
      kind: "status",
      paired: route.paired,
      online: this.ctx.getWebSockets().length === 2,
    });
    for (const s of this.ctx.getWebSockets()) {
      try {
        s.send(message);
      } catch {}
    }
  }
  async fetch(request: Request): Promise<Response> {
    const route = await this.ctx.storage.get<Route>("route"),
      device = request.headers.get("X-Member") ?? "";
    if (
      !route ||
      route.revoked ||
      !route.members.some((m) => m.descriptor.deviceId === device)
    )
      return json({ error: "NOT_A_MEMBER" }, 403);
    for (const old of this.ctx.getWebSockets(device))
      old.close(4001, "Session replaced");
    const pair = new WebSocketPair(),
      client = pair[0],
      server = pair[1];
    this.ctx.acceptWebSocket(server, [device]);
    server.serializeAttachment({ device, window: Date.now(), count: 0 });
    this.status(route);
    return new Response(null, { status: 101, webSocket: client });
  }
  async webSocketMessage(
    socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    const bytes =
      typeof message === "string"
        ? encoder.encode(message).length
        : message.byteLength;
    if (bytes > Number(this.env.MAX_FRAME_BYTES) || bytes === 0) {
      socket.close(1009, "Frame size");
      return;
    }
    const info = socket.deserializeAttachment() as {
      device: string;
      window: number;
      count: number;
    };
    if (Date.now() - info.window > 1000) {
      info.window = Date.now();
      info.count = 0;
    }
    if (++info.count > 200) {
      socket.close(1008, "Rate limit");
      return;
    }
    socket.serializeAttachment(info);
    const route = await this.ctx.storage.get<Route>("route");
    if (!route || route.revoked) {
      socket.close(4003, "Route unavailable");
      return;
    }
    const peers = this.ctx
      .getWebSockets()
      .filter((s) => this.ctx.getTags(s)[0] !== info.device);
    try {
      const packet = JSON.parse(
        typeof message === "string"
          ? message
          : new TextDecoder().decode(message),
      );
      if (!["hello", "consent", "encrypted"].includes(packet.kind)) {
        socket.close(1008, "Invalid frame");
        return;
      }
      if (packet.kind === "encrypted" && !route.paired) {
        socket.close(1008, "Confirmation required");
        return;
      }
      if (packet.kind !== "encrypted" && bytes > 8192) {
        socket.close(1009, "Handshake size");
        return;
      }
      if (!peers.length) {
        socket.send(JSON.stringify({ kind: "waiting" }));
        return;
      }
      for (const peer of peers) peer.send(message);
    } catch {
      socket.close(1008, "Invalid frame");
    }
  }
  async webSocketClose(socket: WebSocket): Promise<void> {
    try {
      socket.close();
    } catch {}
    const route = await this.ctx.storage.get<Route>("route");
    if (route) this.status(route);
  }
  async webSocketError(socket: WebSocket): Promise<void> {
    try {
      socket.close(1011, "Transport error");
    } catch {}
  }
}
