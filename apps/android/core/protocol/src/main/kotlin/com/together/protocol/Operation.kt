package com.together.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

@Serializable data class DeviceDescriptor(val deviceId: String, val userId: String, val initialSpaceId: String,
    val publicKey: String, val displayName: String, val protocolVersion: Int, val initialTimeZoneIdentifier: String? = null) {
    fun validate() { uuid(deviceId); uuid(userId); uuid(initialSpaceId); requireProtocol(publicKey.unbase64().size == 32 && displayName.graphemeCount() <= 80 && protocolVersion in 2..4, "INVALID_DEVICE") }
    val fingerprint: String get() = sha256(publicKey.unbase64()).uppercase().chunked(4).joinToString(" ")
}
class DeviceIdentity(val descriptor: DeviceDescriptor, private val seed: ByteArray) {
    init { descriptor.validate(); requireProtocol(seed.size == 32 && Crypto.publicKey(seed).b64() == descriptor.publicKey, "IDENTITY_MISMATCH") }
    fun sign(bytes: ByteArray): String = Crypto.sign(seed, bytes).b64()
    fun signed(body: JsonObject): JsonObject = buildJsonObject { put("body", body); put("signature", sign(Canonical.bytes(body))) }
    fun sign(operation: SyncOperation) = SignedOperation(operation, sign(Canonical.encode(operation)))
    companion object {
        fun create(seed: ByteArray, userId: String = uid(), spaceId: String = uid(), deviceId: String = uid(), name: String, zone: String) =
            DeviceIdentity(DeviceDescriptor(deviceId, userId, spaceId, Crypto.publicKey(seed).b64(), name, 4, zone), seed)
    }
}
@Serializable data class SyncOperation(val operationId: String, val deviceId: String, val actorId: String,
    val entityId: String, val entityType: String, val operationType: String, val lamportClock: Long,
    val payload: Map<String, JsonObject>, val createdAt: Long) : Comparable<SyncOperation> {
    override fun compareTo(other: SyncOperation): Int = compareValuesBy(this, other, { it.lamportClock }, { it.deviceId }, { it.operationId })
    fun validate() {
        listOf(operationId, deviceId, actorId, entityId).forEach(::uuid)
        requireProtocol(lamportClock in 1 until 9_000_000_000_000_000L && createdAt in -2_208_988_800_000L..32_503_680_000_000L, "OPERATION_BOUNDS")
        requireProtocol(entityType in entityTypes && operationType in operationTypes, "UNKNOWN_OPERATION")
        payload.values.forEach(LogValue::validate)
    }
    companion object {
        val entityTypes = setOf("profile", "task", "recurrenceRule", "wishGrant", "wishItem", "grantAdjustment", "sharedSpace", "mediaAsset", "loveGift", "reserveEntry", "dateEvent", "expense", "recurringBill", "billRevision", "billOccurrence", "financeSettings", "paymentMethod")
        val operationTypes = setOf("create", "patch", "delete", "completeTask", "reopenTask", "requestFulfillment", "confirmFulfillment", "rejectFulfillment")
    }
}
@Serializable data class SignedOperation(val operation: SyncOperation, val signature: String) {
    fun verify(device: DeviceDescriptor) {
        operation.validate()
        requireProtocol(operation.deviceId == device.deviceId && operation.actorId == device.userId && Canonical.encode(operation).size <= 230_000 && Crypto.verify(device.publicKey.unbase64(), signature.unbase64(), Canonical.encode(operation)), "INVALID_OPERATION_SIGNATURE")
    }
    val contentDigest: String get() = sha256(Canonical.encode(this))
}
object LogValue {
    fun string(s: String): JsonObject = tagged("string", JsonPrimitive(s))
    fun integer(i: Long): JsonObject = tagged("integer", JsonPrimitive(i))
    fun date(ms: Long): JsonObject = tagged("date", JsonPrimitive(ms))
    fun bool(v: Boolean): JsonObject = tagged("boolean", JsonPrimitive(v))
    fun data(bytes: ByteArray): JsonObject = tagged("data", JsonPrimitive(bytes.b64()))
    val nil: JsonObject = buildJsonObject { put("null", JsonObject(emptyMap())) }
    private fun tagged(type: String, v: JsonElement) = buildJsonObject { put(type, buildJsonObject { put("_0", v) }) }
    fun value(v: JsonObject?, type: String): JsonPrimitive? = (v?.get(type) as? JsonObject)?.get("_0") as? JsonPrimitive
    fun string(v: JsonObject?): String? = value(v, "string")?.takeIf { it.isString }?.content
    fun long(v: JsonObject?, type: String = "integer"): Long? = value(v, type)?.longOrNull
    fun bytes(v: JsonObject?): ByteArray? = value(v, "data")?.content?.unbase64()
    fun validate(v: JsonObject) {
        requireProtocol(v.size == 1, "INVALID_LOG_VALUE")
        val (kind, nested) = v.entries.single(); requireProtocol(nested is JsonObject, "INVALID_LOG_VALUE")
        val n = nested.jsonObject
        if (kind == "null") { requireProtocol(n.isEmpty(), "INVALID_LOG_VALUE"); return }
        requireProtocol(n.keys == setOf("_0"), "INVALID_LOG_VALUE")
        val p = n.getValue("_0") as? JsonPrimitive ?: throw ProtocolException("INVALID_LOG_VALUE")
        requireProtocol(when (kind) {
            "string", "data" -> p.isString
            "date" -> !p.isString && p.longOrNull in -2_208_988_800_000L..32_503_680_000_000L
            "integer" -> !p.isString && p.longOrNull != null
            "boolean" -> !p.isString && p.booleanOrNull != null
            else -> false
        }, "INVALID_LOG_VALUE")
        if (kind == "data") p.content.unbase64()
    }
}
