package com.together.protocol

import kotlinx.serialization.Serializable
import java.net.URI
import java.time.ZoneId

@Serializable data class NativePartnerContactBody(val version: Int = 1, val transport: String = "iroh-quic",
    val invitationId: String, val descriptor: DeviceDescriptor, val endpointId: String,
    val relayURL: String? = null, val directAddresses: List<String>, val issuedAt: Long, val expiresAt: Long)

/** A routing invitation only: no business operation is authorized by this file. */
@Serializable data class NativePartnerContact(val body: NativePartnerContactBody, val signature: String) {
    fun verify(nowMs: Long = System.currentTimeMillis(), expectedInvitationId: String? = null,
        connectedEndpointId: String? = null) {
        verifySignature(expectedInvitationId, connectedEndpointId)
        requireProtocol(body.expiresAt == body.issuedAt + VALIDITY_MILLISECONDS &&
            nowMs >= body.issuedAt && nowMs < body.expiresAt, "INVITATION_EXPIRED")
    }
    fun verifySignature(expectedInvitationId: String? = null, connectedEndpointId: String? = null) {
        val b = body; uuid(b.invitationId); b.descriptor.validate()
        requireProtocol(b.version == 1 && b.transport == "iroh-quic" &&
            (expectedInvitationId == null || expectedInvitationId == b.invitationId) &&
            (connectedEndpointId == null || connectedEndpointId == b.endpointId) &&
            b.issuedAt in 0 until 8_000_000_000_000_000L &&
            b.expiresAt in listOf(b.issuedAt + VALIDITY_MILLISECONDS, b.issuedAt + 600_000L) &&
            b.descriptor.protocolVersion in listOf(3, 4) && b.descriptor.displayName.isNotEmpty() &&
            Regex("[0-9a-f]{64}").matches(b.endpointId) &&
            b.endpointId != b.descriptor.publicKey.unbase64().joinToString("") { "%02x".format(it) } &&
            b.directAddresses.size <= 32 && b.directAddresses.all { it.isNotEmpty() && it.toByteArray().size <= 128 } &&
            (b.relayURL != null || b.directAddresses.isNotEmpty()) &&
            signature.unbase64().size == 64 && Crypto.verify(b.descriptor.publicKey.unbase64(), signature.unbase64(), Canonical.encode(b)),
            "INVALID_NATIVE_CONTACT")
        ZoneId.of(b.descriptor.initialTimeZoneIdentifier ?: "")
        b.relayURL?.let { relay ->
            val u = URI(relay)
            requireProtocol(relay.toByteArray().size <= 2_048 && u.scheme == "https" && !u.host.isNullOrEmpty() &&
                u.userInfo == null && u.query == null && u.fragment == null, "INVALID_NATIVE_RELAY")
        }
    }
    companion object {
        const val VALIDITY_MILLISECONDS = 28_800_000L
        fun issue(identity: DeviceIdentity, invitationId: String, endpointId: String, relayURL: String?,
            directAddresses: List<String>, nowMs: Long = System.currentTimeMillis()): NativePartnerContact {
            requireProtocol(nowMs in 0 until 8_000_000_000_000_000L, "INVITATION_BOUNDS")
            val body = NativePartnerContactBody(invitationId = invitationId, descriptor = identity.descriptor,
                endpointId = endpointId, relayURL = relayURL, directAddresses = directAddresses,
                issuedAt = nowMs, expiresAt = nowMs + VALIDITY_MILLISECONDS)
            return NativePartnerContact(body, identity.sign(Canonical.encode(body))).also { it.verify(nowMs) }
        }
    }
}
