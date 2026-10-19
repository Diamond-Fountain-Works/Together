package com.together.protocol

import kotlinx.serialization.Serializable
import java.nio.ByteBuffer

@Serializable data class HelloBody(val protocolVersion: Int = 2, val routeId: String, val descriptor: DeviceDescriptor,
    val profileName: String, val ephemeralKey: String, val nonce: String, val replicationVersion: Int? = null, val authorizationDigest: String? = null)
@Serializable data class SignedHello(val body: HelloBody, val signature: String) {
    fun verify(trust: SpaceAuthorization) {
        val b = body; uuid(b.nonce); b.descriptor.validate()
        requireProtocol(b.protocolVersion == 2 && b.replicationVersion == 4 && b.routeId == trust.spaceId && b.authorizationDigest == trust.digest && trust.active(b.descriptor) && b.profileName.length <= 80 && b.ephemeralKey.unbase64().size == 32 && Crypto.verify(b.descriptor.publicKey.unbase64(), signature.unbase64(), Canonical.encode(b)), "INVALID_RELAY_HELLO")
    }
}
@Serializable data class ConsentBody(val transcript: String, val deviceId: String, val approved: Boolean = true)
@Serializable data class SignedConsent(val body: ConsentBody, val signature: String) {
    fun verify(remote: DeviceDescriptor, transcript: String) = requireProtocol(body.deviceId == remote.deviceId && body.transcript == transcript && body.approved && Crypto.verify(remote.publicKey.unbase64(), signature.unbase64(), Canonical.encode(body)), "INVALID_RELAY_CONSENT")
}
@Serializable data class CipherHeader(val version: Int = 2, val sessionId: String, val senderId: String, val recipientId: String, val sequence: Long)
@Serializable data class RelayPacket(val kind: String, val hello: SignedHello? = null, val consent: SignedConsent? = null, val header: CipherHeader? = null, val ciphertext: String? = null)
class SecureChannel(private val identity: DeviceIdentity, private val ephemeral: ByteArray, val local: SignedHello, val remote: SignedHello, trust: SpaceAuthorization) {
    val transcript: String
    private val outgoing: ByteArray; private val incoming: ByteArray
    private var sent = 0L; private var received = 0L
    init {
        local.verify(trust); remote.verify(trust)
        requireProtocol(local.body.descriptor == identity.descriptor && local.body.ephemeralKey == Crypto.xPublic(ephemeral).b64() && remote.body.descriptor.deviceId != identity.descriptor.deviceId, "INVALID_CHANNEL_IDENTITY")
        val hellos = listOf(local, remote).sortedBy { it.body.descriptor.deviceId }
        transcript = sha256(Canonical.encode(hellos))
        val salt = transcript.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val secret = Crypto.xSecret(ephemeral, remote.body.ephemeralKey.unbase64())
        val me = identity.descriptor.deviceId; val peer = remote.body.descriptor.deviceId
        outgoing = Crypto.hkdf(secret, salt, "Together-Relay-2:$me:$peer".toByteArray())
        incoming = Crypto.hkdf(secret, salt, "Together-Relay-2:$peer:$me".toByteArray()); secret.fill(0)
    }
    fun consent(): SignedConsent = ConsentBody(transcript, identity.descriptor.deviceId).let { SignedConsent(it, identity.sign(Canonical.encode(it))) }
    fun seal(bytes: ByteArray): RelayPacket {
        requireProtocol(bytes.size < 360_000 && sent < 4_294_967_294L, "ENCRYPTION_BOUNDS")
        val h = CipherHeader(sessionId = transcript, senderId = local.body.descriptor.deviceId, recipientId = remote.body.descriptor.deviceId, sequence = ++sent)
        val nonce = ByteBuffer.allocate(12).putInt(0).putLong(sent).array()
        return RelayPacket("encrypted", header = h, ciphertext = (nonce + Crypto.aead(true, outgoing, nonce, Canonical.encode(h), bytes)).b64())
    }
    fun open(packet: RelayPacket): ByteArray {
        val h = packet.header ?: throw ProtocolException("MISSING_CIPHER_HEADER")
        val bytes = packet.ciphertext?.unbase64() ?: throw ProtocolException("MISSING_CIPHERTEXT")
        requireProtocol(packet.kind == "encrypted" && h.version == 2 && h.sessionId == transcript && h.senderId == remote.body.descriptor.deviceId && h.recipientId == identity.descriptor.deviceId && h.sequence == received + 1 && bytes.size in 28 until 360_032, "REPLAY_OR_WRONG_SESSION")
        val clear = Crypto.aead(false, incoming, bytes.copyOfRange(0, 12), Canonical.encode(h), bytes.copyOfRange(12, bytes.size))
        received = h.sequence; return clear
    }
    companion object {
        fun hello(identity: DeviceIdentity, ephemeral: ByteArray, trust: SpaceAuthorization) = HelloBody(routeId = trust.spaceId, descriptor = identity.descriptor, profileName = identity.descriptor.displayName, ephemeralKey = Crypto.xPublic(ephemeral).b64(), nonce = uid(), replicationVersion = 4, authorizationDigest = trust.digest).let { SignedHello(it, identity.sign(Canonical.encode(it))) }
    }
}
