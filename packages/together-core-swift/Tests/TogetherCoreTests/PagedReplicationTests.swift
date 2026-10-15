import Foundation
import Testing
@testable import TogetherCore

actor ReplicationTestWire {
    struct Packet:Sendable{let target:Int;let bytes:Data}
    var packets:[Packet]=[]
    var largestFrame=0,largestQueue=0,frames=0
    var dropReceipts=false
    func send(_ frame:ReplicationFrame,to target:Int)throws{
        if dropReceipts,case .acknowledgement = frame{return}
        let bytes=try CanonicalJSON.encode(frame)
        largestFrame=max(largestFrame,bytes.count);frames+=1
        packets.append(Packet(target:target,bytes:bytes));largestQueue=max(largestQueue,packets.count)
    }
    func pop()->Packet?{packets.isEmpty ? nil:packets.removeFirst()}
    func dropAcknowledgements(_ value:Bool){dropReceipts=value}
}
@MainActor func pump(_ wire:ReplicationTestWire,_ sessions:[PagedReplicationSession],limit:Int=100_000)async throws{
    var count=0
    while let packet=await wire.pop(){
        count+=1;#expect(count<limit)
        if count>=limit{throw ReplicationError.bounds}
        try await sessions[packet.target].receive(CanonicalJSON.decode(ReplicationFrame.self,from:packet.bytes))
    }
}
@MainActor func replicationPair(_ f:ReplicationFixture,trust:SpaceAuthorization?=nil)async throws -> (AuthorizedReplicationStore,AuthorizedReplicationStore,DeviceAcknowledgementLedger,DeviceAcknowledgementLedger){
    let trust=try trust ?? SpaceAuthorization(genesis:f.genesis)
    let a=try AuthorizedReplicationStore(repository:TogetherRepository(inMemory:true),identity:f.a,authorization:trust)
    let b=try AuthorizedReplicationStore(repository:TogetherRepository(inMemory:true),identity:f.b,authorization:trust)
    try await a.restore();try await b.restore()
    return (a,b,DeviceAcknowledgementLedger(repository:a.repository,index:a.index,identity:f.a),DeviceAcknowledgementLedger(repository:b.repository,index:b.index,identity:f.b))
}
@Suite("Paged signed-log replication")struct PagedReplicationTests{
    @Test @MainActor func bidirectionalOfflineWritesContentConvergenceAndDurableAck()async throws{
        let f=try ReplicationFixture(),(a,b,al,bl)=try await replicationPair(f),wire=ReplicationTestWire()
        let first=try f.operation(f.a),second=try f.operation(f.b)
        _=try await a.append(first);_=try await b.append(second)
        let before=try await al.partnerHasPersisted(InventoryEntry(first),trust:a.authorization)
        #expect(!before)
        let ab=PagedReplicationSession(store:a,ledger:al,remote:f.b.descriptor,send:{try await wire.send($0,to:1)})
        let ba=PagedReplicationSession(store:b,ledger:bl,remote:f.a.descriptor,send:{try await wire.send($0,to:0)})
        try await ab.synchronize();try await ba.synchronize();try await pump(wire,[ab,ba])
        #expect(try await a.index.checkpoint()==b.index.checkpoint())
        #expect(try await al.partnerHasPersisted(InventoryEntry(first),trust:a.authorization))
        #expect(try await bl.partnerHasPersisted(InventoryEntry(second),trust:b.authorization))
        #expect(await wire.largestFrame<248_192)
        #expect(await wire.largestQueue<16)
        let ac=try await a.projectionContext(),bc=try await b.projectionContext()
        #expect(OperationProjector.replay(try a.repository.allOperations(),context:ac)==OperationProjector.replay(try b.repository.allOperations(),context:bc))
    }
    @Test @MainActor func outOfOrderChainAndDuplicateAreIdempotentAndBackdatedRevokedRecordFails()async throws{
        let f=try ReplicationFixture(),(a,b,_,_)=try await replicationPair(f)
        let one=try await a.append(f.operation(f.a)),two=try await a.append(f.operation(f.a,clock:2))
        try await b.receive([.authorized(two)])
        #expect(try b.repository.operationCount()==0)
        try await b.receive([.authorized(one),.authorized(one)])
        #expect(try b.repository.operationCount()==2)
        try await b.receive([.authorized(two)])
        #expect(try b.repository.operationCount()==2)
        var bad=one;bad.body.sequence=3
        await #expect(throws:ReplicationError.self){try await b.receive([.authorized(bad)])}
    }
    @Test @MainActor func lostReceiptsRecoverWithoutReapplyingOperations()async throws{
        let f=try ReplicationFixture(),(a,b,al,bl)=try await replicationPair(f),wire=ReplicationTestWire()
        let op=try f.operation(f.a);_=try await a.append(op)
        let ab=PagedReplicationSession(store:a,ledger:al,remote:f.b.descriptor,send:{try await wire.send($0,to:1)})
        let ba=PagedReplicationSession(store:b,ledger:bl,remote:f.a.descriptor,send:{try await wire.send($0,to:0)})
        await wire.dropAcknowledgements(true)
        try await ab.synchronize();try await ba.synchronize();try await pump(wire,[ab,ba])
        #expect(try b.repository.operationCount()==1)
        #expect(try await !al.partnerHasPersisted(InventoryEntry(op),trust:a.authorization))
        await wire.dropAcknowledgements(false)
        try await ab.synchronize();try await ba.synchronize();try await pump(wire,[ab,ba])
        #expect(try b.repository.operationCount()==1)
        #expect(try await al.partnerHasPersisted(InventoryEntry(op),trust:a.authorization))
        let receipt=try #require(await bl.receipt(entries:[InventoryEntry(op)],trust:b.authorization))
        _=try await al.accept(receipt,from:f.b.descriptor,trust:a.authorization)
        _=try await al.accept(receipt,from:f.b.descriptor,trust:a.authorization)
        var forged=receipt;forged.signature=try f.a.sign(CanonicalJSON.encode(forged.body))
        await #expect(throws:ReplicationError.invalidReceipt){try await al.accept(forged,from:f.b.descriptor,trust:a.authorization)}
    }
    @Test @MainActor func sealedProtocol3HistoryCanBootstrapWithoutRewritingOriginalBytes()async throws{
        let f=try ReplicationFixture(),original=try f.operation(f.a)
        let body=SpaceGenesisBody(context:f.context,legacyCheckpoint:try ReplicationHash.inventory([InventoryEntry(original)]))
        let trust=try SpaceAuthorization(genesis:SignedSpaceGenesis.sign(body,with:[f.a,f.b]),existingPins:f.context)
        let a=try AuthorizedReplicationStore(repository:TogetherRepository(inMemory:true),identity:f.a,authorization:trust)
        let b=try AuthorizedReplicationStore(repository:TogetherRepository(inMemory:true),identity:f.b,authorization:trust)
        try a.repository.insert([original]);try await a.restore();try await b.restore()
        try await b.receive([.legacy(original)])
        #expect(try CanonicalJSON.encode(b.repository.allOperations()[0])==CanonicalJSON.encode(original))
        let context=try await b.projectionContext();#expect(context.spaceId==f.context.spaceId)
        #expect(OperationProjector.replay(try b.repository.allOperations(),context:context).tasks.count==1)
        await #expect(throws:ReplicationError.unauthorized){try await b.receive([.legacy(f.operation(f.a,clock:2))])}
    }
    @Test @MainActor func stablePagesExcludeConcurrentNewWritesUntilNextPass()async throws{
        let f=try ReplicationFixture(),repo=try TogetherRepository(inMemory:true),index=OperationInventoryIndex(repository:repo)
        var ops:[SignedOperation]=[]
        for i in 0..<260{ops.append(try f.operation(f.a,clock:Int64(i+1)))}
        try repo.insert(ops)
        let frozen=try await index.acquireSnapshot();try repo.insert([f.operation(f.b)])
        var cursor:UUID?,ids:Set<UUID>=[]
        repeat{let page=try await index.page(after:cursor,snapshot:frozen);ids.formUnion(page.entries.map(\.operationId));cursor=page.next}while cursor != nil
        #expect(ids==Set(ops.map(\.id)))
        #expect(try await index.checkpoint().count==261)
        try await index.releaseSnapshot(frozen)
    }
    @Test @MainActor func malformedInventoryDigestAndWrongBatchDoNotAcknowledge()async throws{
        let f=try ReplicationFixture(),(a,_,al,_)=try await replicationPair(f),wire=ReplicationTestWire()
        let session=PagedReplicationSession(store:a,ledger:al,remote:f.b.descriptor,send:{try await wire.send($0,to:1)})
        try await session.synchronize()
        let packet=try #require(await wire.pop())
        guard case .inventoryStart(let id)=try CanonicalJSON.decode(ReplicationFrame.self,from:packet.bytes) else{Issue.record("Missing start");return}
        let bad=InventoryPage(checkpoint:InventoryCheckpoint(count:0,digest:String(repeating:"0",count:64)),after:nil,entries:[],next:nil)
        await #expect(throws:ReplicationError.invalidPage){try await session.receive(.inventoryPage(id,bad))}
        #expect(try a.repository.operationCount()==0)
    }
}
