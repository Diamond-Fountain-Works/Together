import { describe, it, expect } from "vitest";
import vectors from "../../../protocol/fixtures/replication-v4.json";
import {
  canonical,
  sha,
  verifyArchive,
  type AuthorizationArchive,
} from "../src/multidevice";
const text = new TextEncoder();
async function signature(body: unknown, proof: string, key: string) {
  const publicKey = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(atob(key), (x) => x.charCodeAt(0)),
    "Ed25519",
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "Ed25519",
    publicKey,
    Uint8Array.from(atob(proof), (x) => x.charCodeAt(0)),
    text.encode(canonical(body)),
  );
}
describe("Swift CryptoKit to Workers WebCrypto public protocol fixtures", () => {
  it("validates both root signatures and the independent device grant", async () => {
    expect(vectors.synthetic).toBe(true);
    const verified = await verifyArchive(
      vectors.authorization as AuthorizationArchive,
    );
    expect(verified.authorizationDigest).toBe(vectors.authorizationDigest);
    expect(verified.devices).toHaveLength(3);
  });
  it("binds original protocol-3 bytes and outer device authorization separately", async () => {
    const record = vectors.record.authorized,
      body = record.body,
      signed = body.signedOperation;
    const verified = await verifyArchive(
        vectors.authorization as AuthorizationArchive,
      ),
      device = verified.devices.find(
        (d) => d.descriptor.deviceId === signed.operation.deviceId,
      )!;
    expect(
      await signature(body, record.signature, device.descriptor.publicKey),
    ).toBe(true);
    expect(
      await signature(
        signed.operation,
        signed.signature,
        device.descriptor.publicKey,
      ),
    ).toBe(true);
    expect(await sha(signed)).toBe(vectors.inventory.contentDigest);
    expect(await sha(record)).toBe(vectors.inventory.certificationDigest);
    expect(await sha(vectors.record)).toBe(vectors.recordDigest);
  });
  it("reproduces the content-and-certificate inventory and signed persistence receipt", async () => {
    const entry = vectors.inventory,
      bytes = text.encode(
        `Together-Inventory-4\n${entry.operationId}:${entry.contentDigest}:${entry.certificationDigest}\n`,
      );
    const digest = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    )
      .map((x) => x.toString(16).padStart(2, "0"))
      .join("");
    expect(digest).toBe(vectors.checkpoint.digest);
    const signer = vectors.authorization.genesis.body.roots.find(
      (d) => d.deviceId === vectors.receipt.body.deviceId,
    )!;
    expect(
      await signature(
        vectors.receipt.body,
        vectors.receipt.signature,
        signer.publicKey,
      ),
    ).toBe(true);
    expect(vectors.frames.map((f) => f.kind)).toEqual([
      "syncHint",
      "inventoryStart",
      "inventoryPage",
      "inventoryNext",
      "operationRequest",
      "operationBatch",
      "inventoryFinished",
      "acknowledgement",
    ]);
  });
  it("rejects a modified owner claim rather than trusting userId", async () => {
    const archive = structuredClone(
      vectors.authorization,
    ) as AuthorizationArchive;
    archive.events[0].body.device.userId = archive.genesis.body.memberIds.find(
      (x) => x !== archive.events[0].body.ownerId,
    )!;
    await expect(verifyArchive(archive)).rejects.toThrow();
  });
});
