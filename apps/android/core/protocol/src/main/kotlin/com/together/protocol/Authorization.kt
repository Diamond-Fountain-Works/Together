package com.together.protocol

import kotlinx.serialization.Serializable
import java.time.ZoneId

@Serializable data class Checkpoint(val count: Int, val digest: String) {
    fun validate() = requireProtocol(count >= 0 && validDigest(digest), "INVALID_CHECKPOINT")
}
@Serializable data class Frontier(val sequence: Long = 0, val digest: String = "0".repeat(64)) {
    fun validate() = requireProtocol(sequence in 0 until 9_000_000_000_000_000L && validDigest(digest) && (sequence != 0L || digest == "0".repeat(64)), "INVALID_FRONTIER")
}
@Serializable data class DeviceSignature(val deviceId: String, val signature: String)
@Serializable data class GenesisBody(val version: Int, val spaceId: String, val memberIds: List<String>,
    val roots: List<DeviceDescriptor>, val legacySpaceIds: List<String>, val sharedTimeZoneIdentifier: String, val legacyCheckpoint: Checkpoint)
@Serializable data class SignedGenesis(val body: GenesisBody, val signatures: List<DeviceSignature>) {
    val digest get() = sha256(Canonical.encode(this))
    fun verify() {
        val b = body; uuid(b.spaceId); b.memberIds.forEach(::uuid); b.legacySpaceIds.forEach(::uuid)
        requireProtocol(b.version == 4 && b.roots.size == 2 && b.memberIds.size == 2 && b.memberIds.toSet().size == 2 && b.memberIds == b.memberIds.sorted() && b.roots.map { it.userId }.toSet() == b.memberIds.toSet(), "INVALID_GENESIS")
        requireProtocol(b.roots.map { it.deviceId }.distinct().size == 2 && b.roots.map { it.publicKey }.distinct().size == 2 && b.roots.map { it.deviceId } == b.roots.map { it.deviceId }.sorted(), "INVALID_GENESIS")
        requireProtocol(b.legacySpaceIds.size <= 3 && b.legacySpaceIds.distinct().size == b.legacySpaceIds.size && b.legacySpaceIds == b.legacySpaceIds.sorted() && b.spaceId in b.legacySpaceIds, "INVALID_SPACE")
        b.legacyCheckpoint.validate(); ZoneId.of(b.sharedTimeZoneIdentifier)
        requireProtocol(signatures.size == 2 && signatures.map { it.deviceId } == b.roots.map { it.deviceId }, "INVALID_GENESIS_SIGNATURES")
        b.roots.forEach { d -> d.validate(); requireProtocol(Crypto.verify(d.publicKey.unbase64(), signatures.single { it.deviceId == d.deviceId }.signature.unbase64(), Canonical.encode(b)), "INVALID_GENESIS_SIGNATURES") }
    }
}
@Serializable data class AuthorizationBody(val version: Int = 4, val spaceId: String, val ownerId: String, val revision: Long,
    val previousDigest: String, val authorizerDeviceId: String, val action: String, val device: DeviceDescriptor, val epochId: String, val cutoff: Frontier? = null)
@Serializable data class AuthorizationEvent(val body: AuthorizationBody, val signature: String) { val digest get() = sha256(Canonical.encode(this)) }
@Serializable data class AuthorizationArchive(val genesis: SignedGenesis, val events: List<AuthorizationEvent>)
data class AuthorizedDevice(val descriptor: DeviceDescriptor, val epochId: String, val revokedAt: Frontier? = null) { val active get() = revokedAt == null }
class SpaceAuthorization private constructor(val archive: AuthorizationArchive, val devices: Map<String, AuthorizedDevice>) {
    val spaceId get() = archive.genesis.body.spaceId
    val members get() = archive.genesis.body.memberIds.toSet()
    val digest get() = sha256(Canonical.encode(archive))
    fun root(owner: String) = archive.genesis.body.roots.singleOrNull { it.userId == owner }
    fun active(d: DeviceDescriptor) = devices[d.deviceId]?.let { it.active && it.descriptor.publicKey == d.publicKey && it.descriptor.userId == d.userId && it.descriptor.initialSpaceId == d.initialSpaceId } == true
    fun extends(prior: SpaceAuthorization) = archive.genesis == prior.archive.genesis && prior.archive.events.all { it in archive.events }
    companion object {
        fun rootEpoch(space: String, device: String) = stableId("Together-Device-Epoch-4:$space:$device")
        fun restore(archive: AuthorizationArchive): SpaceAuthorization {
            requireProtocol(Canonical.encode(archive).size <= 131_072, "AUTHORIZATION_HISTORY_PAGE_REQUIRED")
            archive.genesis.verify(); val b = archive.genesis.body
            val devices = b.roots.associate { it.deviceId to AuthorizedDevice(it, rootEpoch(b.spaceId, it.deviceId)) }.toMutableMap()
            val revisions = b.memberIds.associateWith { 0L }.toMutableMap(); val heads = b.memberIds.associateWith { archive.genesis.digest }.toMutableMap()
            val seen = mutableSetOf<AuthorizationEvent>()
            archive.events.forEach { event ->
                if (!seen.add(event)) return@forEach
                val e = event.body; val root = b.roots.singleOrNull { it.userId == e.ownerId } ?: throw ProtocolException("NOT_AN_OWNER")
                uuid(e.epochId); e.device.validate()
                requireProtocol(e.version == 4 && e.spaceId == b.spaceId && e.ownerId == e.device.userId && e.authorizerDeviceId == root.deviceId && Crypto.verify(root.publicKey.unbase64(), event.signature.unbase64(), Canonical.encode(e)), "INVALID_DEVICE_AUTHORIZATION")
                requireProtocol(e.revision == revisions.getValue(e.ownerId) + 1 && e.previousDigest == heads[e.ownerId], "AUTHORIZATION_FORK")
                when (e.action) {
                    "grant" -> {
                        requireProtocol(e.device.deviceId !in devices && devices.values.count { it.active } < 32 && e.cutoff == null && devices.values.none { it.descriptor.publicKey == e.device.publicKey || it.epochId == e.epochId }, "INVALID_DEVICE_GRANT")
                        ZoneId.of(e.device.initialTimeZoneIdentifier ?: "")
                        devices[e.device.deviceId] = AuthorizedDevice(e.device, e.epochId)
                    }
                    "revoke" -> {
                        val d = devices[e.device.deviceId] ?: throw ProtocolException("UNKNOWN_DEVICE")
                        requireProtocol(d.active && d.descriptor == e.device && d.epochId == e.epochId && e.device.deviceId != root.deviceId && e.cutoff != null, "INVALID_REVOCATION")
                        e.cutoff!!.validate(); devices[e.device.deviceId] = d.copy(revokedAt = e.cutoff)
                    }
                    else -> throw ProtocolException("UNKNOWN_AUTHORIZATION_ACTION")
                }
                revisions[e.ownerId] = e.revision; heads[e.ownerId] = event.digest
            }
            val ordered = seen.sortedWith(compareBy({ it.body.ownerId }, { it.body.revision }))
            return SpaceAuthorization(AuthorizationArchive(archive.genesis, ordered), devices.toMap())
        }
    }
}
@Serializable data class AuthorizedBody(val version: Int = 4, val spaceId: String, val epochId: String,
    val sequence: Long, val previousDigest: String, val signedOperation: SignedOperation)
@Serializable data class AuthorizedOperation(val body: AuthorizedBody, val signature: String) {
    val digest get() = sha256(Canonical.encode(this))
    fun verify(trust: SpaceAuthorization): AuthorizedDevice {
        val b = body; val d = trust.devices[b.signedOperation.operation.deviceId] ?: throw ProtocolException("UNAUTHORIZED_DEVICE")
        requireProtocol(b.version == 4 && b.spaceId == trust.spaceId && b.sequence in 1 until 9_000_000_000_000_000L && validDigest(b.previousDigest) && (b.sequence != 1L || b.previousDigest == Frontier().digest) && b.epochId == d.epochId, "INVALID_CERTIFICATE")
        b.signedOperation.verify(d.descriptor)
        requireProtocol(Crypto.verify(d.descriptor.publicKey.unbase64(), signature.unbase64(), Canonical.encode(b)), "INVALID_CERTIFICATE_SIGNATURE")
        requireProtocol(d.revokedAt == null || b.sequence <= d.revokedAt.sequence, "DEVICE_REVOKED")
        return d
    }
}
@Serializable data class ReplicationRecord(val kind: String, val legacy: SignedOperation? = null, val authorized: AuthorizedOperation? = null) {
    val operation: SignedOperation get() = when (kind) { "legacy" -> { requireProtocol(authorized == null, "INVALID_RECORD"); legacy ?: throw ProtocolException("INVALID_RECORD") }; "authorized" -> { requireProtocol(legacy == null, "INVALID_RECORD"); authorized?.body?.signedOperation ?: throw ProtocolException("INVALID_RECORD") }; else -> throw ProtocolException("UNSUPPORTED_RECORD") }
    val entry get() = InventoryEntry(operation.operation.operationId, operation.contentDigest, authorized?.digest)
}
