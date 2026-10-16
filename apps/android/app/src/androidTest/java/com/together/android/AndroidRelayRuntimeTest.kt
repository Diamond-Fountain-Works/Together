package com.together.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.protocol.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidRelayRuntimeTest {
    @Test fun roomBackedAndroidReplicasUseRealLocalRelayAndRecoverOffline() = runBlocking {
        val base = InstrumentationRegistry.getArguments().getString("relayURL")
        assumeTrue("Loopback Relay not provided: runtime network NOT RUN", base != null)
        requireProtocol(base!!.startsWith("http://127.0.0.1:"), "ISOLATED_RELAY_REQUIRED")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixture = SyntheticRelaySpace(base)
        val names = List(3) { "qa-relay-${uid()}.db" }
        val databases = names.map { TogetherDatabase.open(context, it) }
        val replicas = listOf(fixture.a, fixture.b, fixture.phone).mapIndexed { index, id -> Replica(RoomReplicaStore(databases[index]), id, fixture.trust).also { it.restore() } }
        fun append(r: Replica, label: String) = r.append(listOf(SyncOperation(uid(), r.identity.descriptor.deviceId, r.identity.descriptor.userId, uid(), "task", "create", r.nextClock(), mapOf("title" to LogValue.string(label), "spaceId" to LogValue.string(fixture.trust.spaceId), "createdBy" to LogValue.string(r.identity.descriptor.userId)), 1791532800000))).single()
        replicas.forEach { append(it, "Synthetic Android runtime task") }
        val clients = replicas.map { r -> val binding = fixture.binding.copy(localDeviceId = r.identity.descriptor.deviceId); C1Client(r, binding, RelayApi(binding, r.identity, true)) }
        val jobs = clients.map { launch(Dispatchers.IO) { it.run() } }
        try {
            withTimeout(60_000) { while (replicas.any { it.inventoryCheckpoint().count != 3 } || clients.any { it.state.value != "connected" }) delay(100) }
            jobs[2].cancelAndJoin()
            val offline = append(replicas[2], "Synthetic offline Android runtime task")
            val restarted = launch(Dispatchers.IO) { clients[2].run() }
            try {
                withTimeout(60_000) { while (replicas.any { it.inventoryCheckpoint().count != 4 } || !replicas[2].partnerPersisted(offline.entry)) delay(100) }
                assertEquals(1, replicas.map { it.inventoryCheckpoint() }.distinct().size)
                assertTrue(replicas[2].partnerPersisted(offline.entry))
            } finally { restarted.cancelAndJoin() }
        } finally {
            jobs.forEach { it.cancel() }; jobs.forEach { it.join() }
            databases.forEach { it.close() }; names.forEach(context::deleteDatabase); fixture.close()
        }
    }
}
