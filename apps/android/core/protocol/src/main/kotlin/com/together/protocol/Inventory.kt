package com.together.protocol

import kotlinx.serialization.Serializable
import java.security.MessageDigest

@Serializable data class InventoryEntry(val operationId: String, val contentDigest: String, val certificationDigest: String? = null) {
    fun validate() { uuid(operationId); requireProtocol(validDigest(contentDigest) && (certificationDigest == null || validDigest(certificationDigest)), "INVALID_INVENTORY_ENTRY") }
    fun line() = "$operationId:$contentDigest${certificationDigest?.let { ":$it" } ?: ""}\n".toByteArray()
}
class InventoryHasher {
    private val hash = MessageDigest.getInstance("SHA-256").apply { update("Together-Inventory-4\n".toByteArray()) }
    private var count = 0; private var last: String? = null
    fun add(entry: InventoryEntry) { entry.validate(); requireProtocol(last == null || last!! < entry.operationId, "INVALID_INVENTORY_ORDER"); last = entry.operationId; hash.update(entry.line()); count++ }
    fun finish() = Checkpoint(count, hash.digest().joinToString("") { "%02x".format(it) })
}
fun checkpoint(entries: List<InventoryEntry>): Checkpoint = InventoryHasher().apply { entries.sortedBy { it.operationId }.forEach(::add) }.finish()
@Serializable data class InventoryPage(val checkpoint: Checkpoint, val entries: List<InventoryEntry>, val after: String? = null, val next: String? = null) {
    fun validate() {
        checkpoint.validate(); entries.forEach { it.validate() }; after?.let(::uuid); next?.let(::uuid)
        requireProtocol(entries.size <= 128 && entries.map { it.operationId }.distinct().size == entries.size && entries.map { it.operationId } == entries.map { it.operationId }.sorted() && entries.all { after == null || it.operationId > after } && (next == null || (entries.isNotEmpty() && next == entries.last().operationId)), "INVALID_INVENTORY_PAGE")
    }
}
@Serializable data class AckBody(val version: Int = 4, val spaceId: String, val deviceId: String, val epochId: String,
    val entries: List<InventoryEntry>, val checkpoint: Checkpoint? = null)
@Serializable data class SignedAck(val body: AckBody, val signature: String) {
    fun verify(trust: SpaceAuthorization, remote: DeviceDescriptor) {
        val b = body; val d = trust.devices[b.deviceId]
        b.entries.forEach { it.validate() }; b.checkpoint?.validate()
        requireProtocol(b.version == 4 && b.spaceId == trust.spaceId && b.deviceId == remote.deviceId && trust.active(remote) && d?.epochId == b.epochId && b.entries.size <= 32 && b.entries.map { it.operationId }.distinct().size == b.entries.size && (if (b.checkpoint == null) b.entries.isNotEmpty() else b.entries.isEmpty()) && Crypto.verify(remote.publicKey.unbase64(), signature.unbase64(), Canonical.encode(b)), "INVALID_RECEIPT")
    }
    val digest get() = sha256(Canonical.encode(this))
}
