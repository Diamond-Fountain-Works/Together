package com.together.protocol

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class NativePartnerPairingTest {
    private fun identity(version: Int): DeviceIdentity {
        val seed = Crypto.seed()
        return DeviceIdentity(DeviceIdentity.create(seed, name = "Synthetic partner", zone = "Asia/Shanghai")
            .descriptor.copy(protocolVersion = version), seed)
    }
    @Test fun mixedRootVersionsUseExplicitPartnerChannelAndRejectReplayTamperAndSameUser() {
        val a=identity(3); val b=identity(4); val route=uid(); val ka=Crypto.seed(); val kb=Crypto.seed()
        fun hello(id:DeviceIdentity,key:ByteArray):SignedHello {
            val body=HelloBody(1,route,id.descriptor,"Synthetic",Crypto.xPublic(key).b64(),uid(),null,null)
            return SignedHello(body,id.sign(Canonical.encode(body)))
        }
        val ha=hello(a,ka);val hb=hello(b,kb)
        assertEquals(hb,Canonical.parse(Canonical.encode(hb)).model<SignedHello>())
        val left=PartnerSecureChannel(a,ka,ha,hb);val right=PartnerSecureChannel(b,kb,hb,ha)
        assertEquals(left.transcript,right.transcript)
        val packet=left.seal("synthetic private payload".toByteArray())
        assertArrayEquals("synthetic private payload".toByteArray(),right.open(packet))
        assertThrows(Exception::class.java){right.open(packet)}
        assertThrows(Exception::class.java){left.open(packet)}
        val forged=hb.copy(body=hb.body.copy(profileName="tampered"))
        assertThrows(Exception::class.java){PartnerSecureChannel(a,ka,ha,forged)}
        val seed=Crypto.seed();val same=DeviceIdentity(DeviceIdentity.create(seed,a.descriptor.userId,name="Same owner",zone="Asia/Shanghai").descriptor,seed)
        assertThrows(Exception::class.java){PartnerSecureChannel(a,ka,ha,hello(same,kb))}
    }

    @Test fun independentPartnersBothInvitationDirectionsPreserveLogsAndActivateExistingC1() = runBlocking {
        val origin=System.getenv("TOGETHER_LOCAL_RELAY_URL")
        assumeTrue("Isolated Worker missing: native invitation integration NOT RUN",origin!=null)
        requireProtocol(origin!!.startsWith("http://127.0.0.1:"),"ISOLATED_RELAY_REQUIRED")
        for (androidInvites in listOf(false,true)) {
            val a=identity(3);val b=identity(4); val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
            class History(val id:DeviceIdentity):PartnerHistory {
                val store=MemoryStore();var peer:DeviceDescriptor?=null;var replica:Replica?=null;var binding:C1Binding?=null
                var prepared:SignedGenesis?=null;var route:PartnerRoute?=null;var crashBeforeActivation=false
                init { repeat(65){i->val op=id.sign(SyncOperation(uid(),id.descriptor.deviceId,id.descriptor.userId,uid(),"task","create",i+1L,
                    mapOf("spaceId" to LogValue.string(id.descriptor.initialSpaceId),"createdBy" to LogValue.string(id.descriptor.userId),"title" to LogValue.string("Synthetic before pairing $i")),1791532800000))
                    store.put(StoredRecord(ReplicationRecord("legacy",legacy=op),true))} }
                override suspend fun pin(peer:DeviceDescriptor,route:PartnerRoute){assertNotEquals(id.descriptor.userId,peer.userId);this.peer=peer}
                override suspend fun rememberRoute(route:PartnerRoute){this.route=route}
                override suspend fun prepare(genesis:SignedGenesis){prepared=genesis}
                override suspend fun pendingGenesis()=prepared
                override suspend fun ownHistory()=store.rows(null,256,true).map{it.record.operation}.filter{it.operation.deviceId==id.descriptor.deviceId}
                override suspend fun importBatch(operations:List<SignedOperation>){store.transaction{operations.forEach{it.verify(peer!!);store.put(StoredRecord(ReplicationRecord("legacy",legacy=it),true))}}}
                override suspend fun checkpoint()=checkpoint(store.rows(null,256,true).map{it.record.entry})
                override suspend fun complete(authorization:AuthorizationArchive,binding:C1Binding){if(crashBeforeActivation)throw ProtocolException("SIMULATED_PROCESS_EXIT");val trust=SpaceAuthorization.restore(authorization);assertEquals(checkpoint(),trust.archive.genesis.body.legacyCheckpoint);this.binding=binding;replica=Replica(store,id,trust).also{it.restore()}}
            }
            val ah=History(a);val bh=History(b)
            var left=PartnerPairingClient(origin,a,"Synthetic Mac",scope,ah,true)
            val right=PartnerPairingClient(origin,b,"Synthetic Android",scope,bh,true)
            try {
                val creator=if(androidInvites)right else left;val joiner=if(androidInvites)left else right
                creator.create();joiner.join(creator.state.value.invitation!!.code)
                withTimeout(20_000){while(left.state.value.stage!="verifying"||right.state.value.stage!="verifying"){delay(20)}}
                assertEquals(left.state.value.verificationCode,right.state.value.verificationCode)
                assertNull(ah.peer);assertNull(bh.peer)
                ah.crashBeforeActivation=androidInvites
                left.confirm();delay(150);assertNull(ah.peer);assertNull(bh.peer)
                right.confirm()
                if(androidInvites){
                    withTimeout(30_000){while(bh.replica==null||ah.prepared==null)delay(20)}
                    left.stop();ah.crashBeforeActivation=false
                    left=PartnerPairingClient(origin,a,"Synthetic restarted Mac",scope,ah,true,ah.peer)
                    left.resume(ah.route!!.routeId)
                }
                try{withTimeout(30_000){while(left.state.value.stage!="paired"||right.state.value.stage!="paired")delay(20)}}
                catch(e:Exception){throw AssertionError("Pairing states ${left.state.value} / ${right.state.value}",e)}
                assertEquals(ah.checkpoint(),bh.checkpoint());assertEquals(130,ah.checkpoint().count)
                assertEquals(ah.replica!!.trust.spaceId,bh.replica!!.trust.spaceId)
                val clients=listOf(ah,bh).map{h->C1Client(h.replica!!,h.binding!!,RelayApi(h.binding!!,h.id,true))}
                val jobs=clients.map{scope.launch{it.run()}}
                try{withTimeout(30_000){while(clients.any{it.state.value!="connected"})delay(30)}}finally{jobs.forEach{it.cancelAndJoin()}}
            } catch(e:Exception) { throw AssertionError("Pairing stages ${left.state.value.stage}:${left.state.value.error} / ${right.state.value.stage}:${right.state.value.error}",e) }
            finally {left.stop();right.stop();scope.cancel()}
        }
    }
}
