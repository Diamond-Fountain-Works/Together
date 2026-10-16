package com.together.protocol

import kotlinx.serialization.Serializable
import java.net.URI

@Serializable data class C1Binding(val serviceURL: String, val spaceId: String, val legacyRouteId: String, val localDeviceId: String) {
    fun validate(allowLocal: Boolean = false) {
        uuid(spaceId); uuid(legacyRouteId); uuid(localDeviceId); validOrigin(serviceURL, allowLocal)
    }
}
fun validOrigin(text: String, allowLocal: Boolean = false): URI {
    val u = URI(text)
    requireProtocol(u.host != null && u.rawUserInfo == null && u.rawQuery == null && u.rawFragment == null && u.rawPath in listOf("", "/") && (u.scheme == "https" || (allowLocal && u.scheme == "http" && u.host in listOf("localhost", "127.0.0.1", "[::1]"))), "INVALID_RELAY_ORIGIN")
    return u
}
@Serializable data class OfferBody(val kind: String = "Together-Device-Offer-1", val id: String, val issuerDeviceId: String,
    val ownerId: String, val archive: AuthorizationArchive, val binding: C1Binding, val expiresAt: Long)
@Serializable data class EnrollmentOffer(val body: OfferBody, val signature: String) {
    val digest get() = sha256(Canonical.encode(this))
    val code get() = digest.take(24).uppercase().chunked(4).joinToString(" ")
    fun verify(now: Long? = null, allowLocal: Boolean = false): SpaceAuthorization {
        val trust = SpaceAuthorization.restore(body.archive); val root = trust.root(body.ownerId) ?: throw ProtocolException("NOT_AN_OWNER")
        body.binding.validate(allowLocal); uuid(body.id)
        requireProtocol(body.kind == "Together-Device-Offer-1" && body.binding.spaceId == trust.spaceId && body.issuerDeviceId == root.deviceId && body.binding.localDeviceId == root.deviceId && trust.active(root) && Crypto.verify(root.publicKey.unbase64(), signature.unbase64(), Canonical.encode(body)), "INVALID_OFFER")
        requireProtocol(now == null || now < body.expiresAt, "OFFER_EXPIRED")
        return trust
    }
}
@Serializable data class EnrollmentRequestBody(val kind: String = "Together-Device-Request-1", val offerId: String, val offerDigest: String, val device: DeviceDescriptor)
@Serializable data class EnrollmentRequest(val body: EnrollmentRequestBody, val signature: String) {
    val digest get() = sha256(Canonical.encode(this))
    val code get() = digest.take(24).uppercase().chunked(4).joinToString(" ")
    fun verify(offer: EnrollmentOffer, now: Long? = null, allowLocal: Boolean = false) {
        val trust = offer.verify(now, allowLocal); val d = body.device; d.validate()
        requireProtocol(body.kind == "Together-Device-Request-1" && body.offerId == offer.body.id && body.offerDigest == offer.digest && d.userId == offer.body.ownerId && d.initialSpaceId == trust.spaceId && d.protocolVersion == 4 && d.displayName.isNotEmpty() && d.deviceId !in trust.devices && Crypto.verify(d.publicKey.unbase64(), signature.unbase64(), Canonical.encode(body)), "INVALID_ENROLLMENT_REQUEST")
    }
    companion object {
        fun create(offer: EnrollmentOffer, identity: DeviceIdentity, now: Long, allowLocal: Boolean = false): EnrollmentRequest {
            val body = EnrollmentRequestBody(offerId = offer.body.id, offerDigest = offer.digest, device = identity.descriptor)
            return EnrollmentRequest(body, identity.sign(Canonical.encode(body))).also { it.verify(offer, now, allowLocal) }
        }
    }
}
@Serializable data class CompletionBody(val kind: String = "Together-Device-Completion-1", val requestDigest: String, val archive: AuthorizationArchive, val binding: C1Binding)
@Serializable data class EnrollmentCompletion(val body: CompletionBody, val signature: String) {
    fun verify(request: EnrollmentRequest, offer: EnrollmentOffer, allowLocal: Boolean = false): SpaceAuthorization {
        request.verify(offer, allowLocal = allowLocal)
        val prior = offer.verify(allowLocal = allowLocal); val trust = SpaceAuthorization.restore(body.archive)
        body.binding.validate(allowLocal)
        val root = trust.root(offer.body.ownerId) ?: throw ProtocolException("NOT_AN_OWNER")
        requireProtocol(body.kind == "Together-Device-Completion-1" && body.requestDigest == request.digest && trust.extends(prior) && trust.active(request.body.device) && body.binding.localDeviceId == request.body.device.deviceId && body.binding.spaceId == trust.spaceId && body.binding.serviceURL == offer.body.binding.serviceURL && body.binding.legacyRouteId == offer.body.binding.legacyRouteId && Crypto.verify(root.publicKey.unbase64(), signature.unbase64(), Canonical.encode(body)), "INVALID_COMPLETION")
        return trust
    }
}
