package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhysicalReliabilityTest {
    /** Faults close only this test socket; no phone-wide network/radio setting is changed. */
    private class Link : SyncTransport {
        val delegate = OkHttpSyncTransport()
        @Volatile var offline = false
        val connects = AtomicInteger()
        override val state
            get() = delegate.state

        override suspend fun connect(url: String, ticket: String) {
            connects.incrementAndGet()
            requireProtocol(!offline, "QA_LINK_DOWN")
            delegate.connect(url, ticket)
        }

        override suspend fun receive() = delegate.receive()

        override suspend fun send(bytes: ByteArray) {
            requireProtocol(!offline, "QA_LINK_DOWN")
            delegate.send(bytes)
        }

        override fun disconnect() = delegate.disconnect()
    }

    @Test
    fun realRoomSocketsRecoverLinkLossRepeatedConnectCancellationAndPagedCatchup() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        Assume.assumeTrue(
            "Physical reliability is explicitly orchestrated",
            args.getString("runReliability") == "true",
        )
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val base = args.getString("relayURL") ?: error("Loopback Relay required")
        val stages = mutableListOf<JsonObject>()
        var stage = "setup"
        var status = "FAIL"
        val started = android.os.SystemClock.elapsedRealtime()
        fun elapsed() = android.os.SystemClock.elapsedRealtime() - started
        SyntheticRelaySpace(base).use { f ->
            val names = List(3) { "qa-reliability-${uid()}.db" }
            val dbs = names.map { TogetherDatabase.open(context, it) }
            val replicas =
                listOf(f.a, f.b, f.phone).mapIndexed { i, id ->
                    Replica(RoomReplicaStore(dbs[i]), id, f.trust).also { it.restore() }
                }
            val links = List(3) { Link() }
            val clients = replicas.mapIndexed { i, r ->
                val b = f.binding.copy(localDeviceId = r.identity.descriptor.deviceId)
                C1Client(r, b, RelayApi(b, r.identity, true), links[i])
            }
            val jobs = clients.map { launch(Dispatchers.IO) { it.run() } }.toMutableList()
            val observers = clients.mapIndexed { i, c ->
                launch {
                    c.state.collect { state ->
                        stages.add(
                            buildJsonObject {
                                put("ms", elapsed())
                                put("deviceIndex", i)
                                put("state", state)
                                put("error", c.error.value)
                            }
                        )
                    }
                }
            }
            fun append(index: Int, quantity: Int = 1): List<ReplicationRecord> {
                val r = replicas[index]
                val first = r.nextClock()
                return r.append(
                    (0 until quantity).map { offset ->
                        SyncOperation(
                            uid(),
                            r.identity.descriptor.deviceId,
                            r.identity.descriptor.userId,
                            uid(),
                            "task",
                            "create",
                            first + offset,
                            mapOf(
                                "spaceId" to logId(f.trust.spaceId),
                                "createdBy" to logId(r.identity.descriptor.userId),
                                "title" to LogValue.string("Synthetic physical catch-up"),
                            ),
                            1791518400000,
                        )
                    }
                )
            }
            suspend fun waitFor(name: String, predicate: () -> Boolean) {
                stage = name
                try {
                    withTimeout(60_000) { while (!predicate()) delay(100) }
                } finally {
                    android.util.Log.i(
                        "TogetherPhysicalQa",
                        "reliability stage=$name elapsedMs=${elapsed()} counts=${replicas.map{it.inventoryCheckpoint().count}} states=${clients.map{it.state.value to it.error.value}}",
                    )
                }
            }
            try {
                replicas.indices.forEach { append(it) }
                clients.forEach { it.changed() }
                waitFor("initial three sessions") {
                    replicas.all { it.inventoryCheckpoint().count == 3 } &&
                        clients.all { it.state.value == "connected" }
                }
                links[2].offline = true
                links[2].disconnect()
                waitFor("owned link lost") { clients[2].state.value == "offline" }
                val offline = append(2).single()
                append(1)
                clients[1].changed()
                waitFor("others continue while phone link down") {
                    replicas[0].inventoryCheckpoint().count == 4
                }
                links[2].offline = false
                waitFor("automatic backoff recovery") {
                    replicas.all { it.inventoryCheckpoint().count == 5 } &&
                        replicas[2].partnerPersisted(offline.entry)
                }
                // Abrupt WebSocket cancellation, still-enabled foreground owner, automatic new
                // ticket.
                links[2].disconnect()
                val socketClose = append(0).single()
                clients[0].changed()
                waitFor("unexpected websocket close recovery") {
                    replicas.all { it.inventoryCheckpoint().count == 6 } &&
                        replicas[0]
                            .persistedDevices(socketClose.entry)
                            .contains(f.phone.descriptor.deviceId)
                }
                // Overlap cancellation and new run calls without joining at the caller. runLock
                // must
                // protect the old channel cleanup from erasing the new session.
                repeat(8) {
                    val old = jobs[2]
                    old.cancel()
                    jobs[2] = launch(Dispatchers.IO) { clients[2].run() }
                    val duplicate = launch(Dispatchers.IO) { clients[2].run() }
                    delay(15)
                    duplicate.cancelAndJoin()
                    old.join()
                }
                val afterRace = append(2).single()
                clients[2].changed()
                waitFor("cancellation duplicate connect race") {
                    replicas.all { it.inventoryCheckpoint().count == 7 } &&
                        replicas[2].partnerPersisted(afterRace.entry)
                }
                jobs[2].cancelAndJoin()
                // 1,025 new facts exceed an inventory page and operation-batch bounds.
                repeat(32) { append(2, 32) }
                val last = append(2).single()
                jobs[2] = launch(Dispatchers.IO) { clients[2].run() }
                waitFor("1025 operation catchup") {
                    replicas.all { it.inventoryCheckpoint().count == 1032 } &&
                        replicas[2].partnerPersisted(last.entry)
                }
                assertEquals(1, replicas.map { it.inventoryCheckpoint() }.distinct().size)
                jobs.forEach { it.cancel() }
                jobs.forEach { it.join() }
                // Deliberate protocol ACK loss after actual durable receipt. This subcase is an
                // in-process frame pump on physical Room, not a false claim of packet loss in TCP.
                val record = append(0).single()
                assertFalse(replicas[0].partnerPersisted(record.entry))
                fun sync(dropAck: Boolean) {
                    val sessions =
                        listOf(
                            AntiEntropy(replicas[0], f.b.descriptor),
                            AntiEntropy(replicas[1], f.a.descriptor),
                        )
                    try {
                        val queue = java.util.ArrayDeque<Pair<Int, ReplicationFrame>>()
                        sessions.forEachIndexed { i, s ->
                            s.start().forEach { queue.add((1 - i) to it) }
                        }
                        var frames = 0
                        while (queue.isNotEmpty()) {
                            assertTrue("Bounded frame pump", frames++ < 10_000)
                            val (target, frame) = queue.removeFirst()
                            if (dropAck && frame.kind == "acknowledgement") continue
                            sessions[target].receive(frame).forEach {
                                queue.add((1 - target) to it)
                            }
                        }
                    } finally {
                        sessions.forEach { it.close() }
                    }
                }
                sync(true)
                assertNotNull(replicas[1].store.get(record.operation.operation.operationId))
                assertFalse(replicas[0].partnerPersisted(record.entry))
                sync(false)
                assertTrue(replicas[0].partnerPersisted(record.entry))
                val ack = replicas[1].receipt(listOf(record.entry))!!
                assertTrue(replicas[0].acceptAck(ack, f.b.descriptor))
                assertTrue(replicas[0].acceptAck(ack, f.b.descriptor))
                val checkpoint = replicas[1].inventoryCheckpoint()
                replicas[1].receive(listOf(record, record))
                assertEquals(checkpoint, replicas[1].inventoryCheckpoint())
                stage = "complete"
                status = "PASS"
            } finally {
                jobs.forEach { it.cancel() }
                jobs.forEach { it.join() }
                observers.forEach { it.cancelAndJoin() }
                File(context.filesDir, "phase-c-reliability.json")
                    .writeBytes(
                        Canonical.bytes(
                            buildJsonObject {
                                put("status", status)
                                put("stage", stage)
                                put("elapsedMs", elapsed())
                                put("events", JsonArray(stages))
                                put(
                                    "connectAttempts",
                                    buildJsonArray { links.forEach { add(it.connects.get()) } },
                                )
                                put(
                                    "finalCounts",
                                    buildJsonArray {
                                        replicas.forEach { add(it.inventoryCheckpoint().count) }
                                    },
                                )
                                put(
                                    "networkFaultScope",
                                    "owned test socket only; USB reverse, no radio changes",
                                )
                            }
                        )
                    )
                dbs.forEach { it.close() }
            }
        }
    }
}
