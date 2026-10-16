package com.together.protocol

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.TimeUnit

/** Actual loopback Wrangler/DO/WebSocket runtime, synthetic identities only.
 * Legacy route provisioning is a test helper, never Android Protocol 3 sync. */
class LocalRelayIntegrationTest {
    @Test fun threeDevicesAuthenticateEncryptCatchUpAndKeepIndependentSessions() = runBlocking {
        val base = System.getenv("TOGETHER_LOCAL_RELAY_URL")
        assumeTrue("Local Wrangler URL missing; integration NOT RUN", base != null)
        requireProtocol(base!!.startsWith("http://127.0.0.1:"), "ISOLATED_RELAY_REQUIRED")
        fun root(i: Int): DeviceIdentity { val seed = Crypto.seed(); val d = DeviceIdentity.create(seed, name = "Synthetic root $i", zone = "Asia/Shanghai").descriptor.copy(protocolVersion = 3); return DeviceIdentity(d, seed) }
        val a = root(1); val b = root(2)
        val http = OkHttpClient.Builder().followRedirects(false).callTimeout(10, TimeUnit.SECONDS).build()
        fun request(identity: DeviceIdentity, method: String, path: String, body: JsonElement = JsonObject(emptyMap())): JsonObject {
            fun get(r: Request): JsonObject = http.newCall(r).execute().use { response ->
                val raw = response.body!!.bytes(); requireProtocol(response.isSuccessful, "TEST_HTTP_${response.code}"); Canonical.parse(raw, 131072).jsonObject
            }
            val challenge = get(Request.Builder().url(base + if (path.startsWith("/v2/")) "/v2/challenge" else "/v1/challenge").build())
            val bytes = if (method == "GET") byteArrayOf() else Canonical.bytes(body)
            val message = listOf("Together-Auth-1", challenge.getValue("nonce").jsonPrimitive.content, method, path, sha256(bytes), identity.descriptor.deviceId).joinToString("\n")
            return get(Request.Builder().url(base + path).header("X-Together-Key", identity.descriptor.publicKey).header("X-Together-Device", identity.descriptor.deviceId)
                .header("X-Together-Challenge", challenge.getValue("id").jsonPrimitive.content).header("X-Together-Signature", identity.sign(message.toByteArray()))
                .method(method, if (method == "GET") null else bytes.toRequestBody("application/json".toMediaType())).build())
        }
        val invite = request(a, "POST", "/v1/invitations", buildJsonObject { put("descriptor", a.descriptor.json()); put("profileName", "Synthetic A") })
        request(b, "POST", "/v1/invitations/join", buildJsonObject { put("descriptor", b.descriptor.json()); put("profileName", "Synthetic B"); put("code", invite.getValue("code")) })
        val route = invite.getValue("routeId").jsonPrimitive.content
        for (root in listOf(a, b)) request(root, "POST", "/v1/routes/$route/confirm", buildJsonObject { put("transcript", "b".repeat(64)) })
        val old = testTrust(a, b); val bindingA = C1Binding(base, old.spaceId, route, a.descriptor.deviceId); val api = RelayApi(bindingA, a, true)
        api.request("POST", "/v2/spaces", Canonical.bytes(buildJsonObject { put("legacyRouteId", route); put("authorization", old.archive.json()) }))
        val phone = DeviceIdentity.create(Crypto.seed(), a.descriptor.userId, old.spaceId, name = "Synthetic Android", zone = "Asia/Shanghai")
        val grantBody = AuthorizationBody(spaceId = old.spaceId, ownerId = a.descriptor.userId, revision = 1, previousDigest = old.archive.genesis.digest, authorizerDeviceId = a.descriptor.deviceId, action = "grant", device = phone.descriptor, epochId = uid())
        val granted = api.authorize(AuthorizationEvent(grantBody, a.sign(Canonical.encode(grantBody)))).verify(a.descriptor, old)
        val replicas = listOf(a, b, phone).map { Replica(MemoryStore(), it, granted).also { r -> r.restore() } }
        fun append(r: Replica, tag: String) = r.append(listOf(SyncOperation(uid(), r.identity.descriptor.deviceId, r.identity.descriptor.userId, uid(), "task", "create", r.nextClock(), mapOf("spaceId" to LogValue.string(granted.spaceId), "createdBy" to LogValue.string(r.identity.descriptor.userId), "title" to LogValue.string("Synthetic $tag")), 1791532800000))).single()
        replicas.forEachIndexed { i, r -> append(r, "offline $i") }
        val clients = replicas.map { r -> val binding = bindingA.copy(localDeviceId = r.identity.descriptor.deviceId); C1Client(r, binding, RelayApi(binding, r.identity, true)) }
        val jobs = clients.map { launch(Dispatchers.IO) { it.run() } }
        try {
            withTimeout(60_000) { while (replicas.any { it.inventoryCheckpoint().count != 3 } || clients.any { it.state.value != "connected" }) delay(100) }
            assertEquals(3, replicas.map { it.inventoryCheckpoint() }.distinct().single().count)
            jobs[2].cancelAndJoin(); val offline = append(replicas[2], "phone offline"); val other = append(replicas[1], "partner online"); clients[1].changed()
            withTimeout(30_000) { while (replicas[0].inventoryCheckpoint().count != 4) delay(100) }
            val rejoin = launch(Dispatchers.IO) { clients[2].run() }
            try {
                withTimeout(60_000) { while (replicas.any { it.inventoryCheckpoint().count != 5 } || (!replicas[2].partnerPersisted(offline.entry) || !replicas[2].partnerPersisted(other.entry))) delay(100) }
                assertEquals(5, replicas.map { it.inventoryCheckpoint() }.distinct().single().count)
                assertTrue(replicas[2].partnerPersisted(other.entry)); assertEquals(a.descriptor.userId, phone.descriptor.userId)
            } finally { rejoin.cancelAndJoin() }
        } catch (e: Exception) {
            throw AssertionError("Isolated states=" + clients.map { it.state.value to it.error.value } + "; counts=" + replicas.map { it.inventoryCheckpoint().count }, e)
        } finally { jobs.forEach { it.cancel() }; jobs.forEach { it.join() }; http.dispatcher.executorService.shutdown() }
    }
}
