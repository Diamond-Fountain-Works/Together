package com.together.protocol

import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import java.util.concurrent.TimeUnit

/** TEST ONLY: private random synthetic roots exist only in the test process.
 * This fixture is not an application pairing service or a production bootstrap. */
class SyntheticRelaySpace(val base: String) : AutoCloseable {
    val a: DeviceIdentity; val b: DeviceIdentity; val phone: DeviceIdentity
    val trust: SpaceAuthorization; val binding: C1Binding
    private val http = OkHttpClient.Builder().followRedirects(false).callTimeout(15, TimeUnit.SECONDS).build()
    init {
        requireProtocol(base.startsWith("http://127.0.0.1:"), "ISOLATED_RELAY_REQUIRED")
        fun root(name: String): DeviceIdentity {
            val seed = Crypto.seed(); val id = DeviceIdentity.create(seed, name = name, zone = "Asia/Shanghai")
            return DeviceIdentity(id.descriptor.copy(protocolVersion = 3), seed)
        }
        a = root("Synthetic root A"); b = root("Synthetic root B")
        val invitation = request(a, "POST", "/v1/invitations", buildJsonObject { put("descriptor", a.descriptor.json()); put("profileName", "Synthetic A") })
        request(b, "POST", "/v1/invitations/join", buildJsonObject { put("descriptor", b.descriptor.json()); put("profileName", "Synthetic B"); put("code", invitation.getValue("code")) })
        val route = invitation.getValue("routeId").jsonPrimitive.content
        listOf(a, b).forEach { request(it, "POST", "/v1/routes/$route/confirm", buildJsonObject { put("transcript", "b".repeat(64)) }) }
        val space = stableId("space:" + listOf(a.descriptor.deviceId, b.descriptor.deviceId).sorted().joinToString(":"))
        val body = GenesisBody(4, space, listOf(a.descriptor.userId, b.descriptor.userId).sorted(), listOf(a.descriptor, b.descriptor).sortedBy { it.deviceId }, listOf(space, a.descriptor.initialSpaceId, b.descriptor.initialSpaceId).sorted(), "Asia/Shanghai", checkpoint(emptyList()))
        val genesis = SignedGenesis(body, listOf(a, b).sortedBy { it.descriptor.deviceId }.map { DeviceSignature(it.descriptor.deviceId, it.sign(Canonical.encode(body))) })
        val old = SpaceAuthorization.restore(AuthorizationArchive(genesis, emptyList()))
        binding = C1Binding(base, space, route, a.descriptor.deviceId)
        val api = RelayApi(binding, a, true)
        api.request("POST", "/v2/spaces", Canonical.bytes(buildJsonObject { put("legacyRouteId", route); put("authorization", old.archive.json()) }))
        phone = DeviceIdentity.create(Crypto.seed(), a.descriptor.userId, space, name = "Synthetic Android", zone = "Asia/Shanghai")
        val grant = AuthorizationBody(spaceId = space, ownerId = a.descriptor.userId, revision = 1, previousDigest = genesis.digest, authorizerDeviceId = a.descriptor.deviceId, action = "grant", device = phone.descriptor, epochId = uid())
        trust = api.authorize(AuthorizationEvent(grant, a.sign(Canonical.encode(grant)))).verify(a.descriptor, old)
    }
    private fun request(identity: DeviceIdentity, method: String, path: String, body: JsonElement): JsonObject {
        fun fetch(r: Request) = http.newCall(r).execute().use { response ->
            val raw = response.body!!.bytes(); requireProtocol(response.isSuccessful, "TEST_HTTP_${response.code}"); Canonical.parse(raw, 131072).jsonObject
        }
        val challenge = fetch(Request.Builder().url("$base/v1/challenge").build())
        val bytes = Canonical.bytes(body)
        val message = listOf("Together-Auth-1", challenge.getValue("nonce").jsonPrimitive.content, method, path, sha256(bytes), identity.descriptor.deviceId).joinToString("\n")
        return fetch(Request.Builder().url(base + path).header("X-Together-Key", identity.descriptor.publicKey).header("X-Together-Device", identity.descriptor.deviceId)
            .header("X-Together-Challenge", challenge.getValue("id").jsonPrimitive.content).header("X-Together-Signature", identity.sign(message.toByteArray()))
            .method(method, bytes.toRequestBody("application/json".toMediaType())).build())
    }
    override fun close() { http.connectionPool.evictAll(); http.dispatcher.executorService.shutdown() }
}
