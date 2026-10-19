package com.together.android

import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import org.junit.Assert.*
import org.junit.Test

class PartnerRecoveryTest {
    @Test fun pendingVerifiedPartnerHistorySurvivesRoomAndKeystoreReopen()=runBlocking {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val namespace=uid();val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
        var repo=TogetherRepository(context,scope,namespace)
        try {
            withTimeout(10000){repo.state.first{it.loaded}}
            repo.saveTask(title="Synthetic retained own task")
            val original=repo.state.value.descriptor!!;repo.close()
            val peer=DeviceIdentity.create(Crypto.seed(),name="Synthetic confirmed partner",zone="Asia/Shanghai")
            val db=TogetherDatabase.open(context,"qa-$namespace-together-local.db")
            try{
                val store=RoomReplicaStore(db)
                val op=peer.sign(SyncOperation(uid(),peer.descriptor.deviceId,peer.descriptor.userId,uid(),"task","create",100,
                    mapOf("spaceId" to LogValue.string(peer.descriptor.initialSpaceId),"createdBy" to LogValue.string(peer.descriptor.userId),"title" to LogValue.string("Synthetic retained partner history")),1791532800000))
                store.transaction{
                    store.local("partner-peer",Canonical.encode(peer.descriptor));store.local("partner-pending",byteArrayOf(1))
                    store.put(StoredRecord(ReplicationRecord("legacy",legacy=op),true))
                }
            }finally{db.close()}
            repo=TogetherRepository(context,scope,namespace)
            withTimeout(10000){repo.state.first{it.loaded}}
            assertNull(repo.state.value.error);assertEquals(original,repo.state.value.descriptor)
            assertEquals(2,repo.state.value.snapshot.of("task").size)
            assertFalse(repo.state.value.canWrite);assertNull(repo.state.value.authorization)
        } finally {repo.close();scope.cancel()}
    }
}
