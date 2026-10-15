import Foundation
import CryptoKit

public enum ReplicationRecord: Codable, Equatable, Sendable {
    case legacy(SignedOperation)
    case authorized(AuthorizedOperation)
    public var operation: SignedOperation { switch self { case .legacy(let value):value;case .authorized(let value):value.body.signedOperation } }
}

/// A verified public authorization stream plus the existing operation database.
/// All writes use its one owning MainActor context; crypto runs on this actor.
public actor AuthorizedReplicationStore {
    public nonisolated let repository: TogetherRepository
    public nonisolated let index: OperationInventoryIndex
    public nonisolated let identity: DeviceIdentity
    public private(set) var authorization: SpaceAuthorization
    private var legacySealed = false
    private var legacyCount:Int?
    private var locked=false
    private var waiters:[CheckedContinuation<Void,Never>]=[]
    private let prefix = "replication4/"
    public init(repository: TogetherRepository, identity: DeviceIdentity, authorization: SpaceAuthorization) throws {
        guard authorization.containsActive(identity.descriptor) else { throw ReplicationError.unauthorized }
        self.repository = repository; self.identity = identity; self.authorization = authorization
        index = OperationInventoryIndex(repository: repository)
    }
    public func restore() async throws {
        await lock();defer{unlock()};try Task.checkCancellation()
        if let archive = try await repository.load(AuthorizationArchive.self,key:prefix+"authorization") {
            let verified = try SpaceAuthorization.restore(archive)
            guard try verified.genesis.digest == authorization.genesis.digest else { throw ReplicationError.unauthorized }
            authorization = verified
        } else { try await repository.save(authorization.archive,key:prefix+"authorization") }
        legacySealed = try await repository.load(String.self,key:prefix+"legacy-seal") == authorization.genesis.body.legacyCheckpoint.digest
        if !legacySealed {
            let checkpoint = try await index.checkpoint()
            if checkpoint == authorization.genesis.body.legacyCheckpoint {
                // Existing pair migration: seal exact bytes already in this
                // database. New devices first download the complete baseline.
                var cursor: UUID?
                repeat {
                    let page = try await index.page(after:cursor,checkpoint:checkpoint)
                    var records: [String:Data] = [:]
                    for entry in page.entries { records[legacyKey(entry.operationId)] = try CanonicalJSON.encode(entry.contentDigest) }
                    try await repository.saveAtomically(records); cursor = page.next
                } while cursor != nil
                try await sealLegacyIfComplete()
            }
        }
        try await refreshVisibility();try await promote()
    }
    public func updateAuthorization(_ archive: AuthorizationArchive) async throws {
        await lock();defer{unlock()};try Task.checkCancellation()
        let verified = try SpaceAuthorization.restore(archive)
        guard try verified.genesis.digest == authorization.genesis.digest,
              authorization.events.allSatisfy({ verified.events.contains($0) }) else { throw ReplicationError.staleAuthorization }
        try await repository.save(verified.archive,key:prefix+"authorization"); authorization = verified
        try await refreshVisibility()
        try await promote()
    }
    private func refreshVisibility()async throws{
        var cursor:String?,excluded:Set<UUID>=[]
        repeat{
            let rows=try await repository.localPage(prefix:prefix+"proof/",after:cursor,limit:256)
            for row in rows{let proof=try CanonicalJSON.decode(AuthorizedOperation.self,from:row.bytes);if (try? proof.verify(in:authorization))==nil{excluded.insert(proof.id)}}
            cursor=rows.count==256 ? rows.last?.id:nil
        }while cursor != nil
        await index.exclude(excluded)
    }
    public func isActive(_ device: DeviceDescriptor) -> Bool { authorization.containsActive(device) }
    private func legacyKey(_ id: UUID) -> String { prefix+"legacy/"+id.uuidString }
    private func proofKey(_ id: UUID) -> String { prefix+"proof/"+id.uuidString }
    private func stageKey(_ id: UUID) -> String { prefix+"stage/"+id.uuidString }
    private func sequenceKey(_ body: AuthorizedOperationBody) -> String {
        sequenceKey(epoch:body.epochId,sequence:body.sequence)
    }
    private func sequenceKey(epoch:UUID,sequence:Int64) -> String {prefix+"sequence/"+epoch.uuidString+"/"+String(format:"%020lld",sequence)}
    private func headKey(_ epoch: UUID) -> String { prefix+"head/"+epoch.uuidString }
    public func frontier(deviceId: UUID) async throws -> DeviceFrontier {
        guard let device = authorization.devices[deviceId] else { throw ReplicationError.unauthorized }
        return try await repository.load(DeviceFrontier.self,key:headKey(device.epochId)) ?? DeviceFrontier()
    }
    public func record(for operation: SignedOperation) async throws -> ReplicationRecord {
        if let proof = try await repository.load(AuthorizedOperation.self,key:proofKey(operation.id)) {
            guard proof.body.signedOperation == operation else { throw ReplicationError.contentCollision }
            _ = try proof.verify(in:authorization);return .authorized(proof)
        }
        guard try await repository.load(String.self,key:legacyKey(operation.id)) == InventoryEntry(operation).contentDigest else { throw ReplicationError.unauthorized }
        return .legacy(operation)
    }
    public func records(_ entries: [InventoryEntry]) async throws -> [ReplicationRecord] {
        let ops = try await index.operations(entries)
        var result:[ReplicationRecord]=[],bytes=0
        for op in ops {
            let value = try await record(for:op), size = try CanonicalJSON.encode(value).count
            if bytes+size > ReplicationProtocol.maximumBatchBytes { break }
            bytes += size;result.append(value)
        }
        guard !result.isEmpty || entries.isEmpty else { throw ReplicationError.bounds };return result
    }
    public func missing(_ entries: [InventoryEntry]) async throws -> [InventoryEntry] {
        let absent = try await index.missing(entries);var result:[InventoryEntry]=[]
        for entry in absent {
            if let staged = try await repository.load(ReplicationRecord.self,key:stageKey(entry.operationId)) {
                guard try InventoryEntry(staged.operation)==entry else {throw ReplicationError.contentCollision}
            } else {result.append(entry)}
        };return result
    }
    /// Records may arrive out of sequence. Their verified bytes are staged
    /// durably; only a certified contiguous prefix becomes business facts.
    public func receive(_ records:[ReplicationRecord]) async throws {
        await lock();defer{unlock()};try Task.checkCancellation()
        guard records.count<=ReplicationProtocol.operationBatchSize,
              try CanonicalJSON.encode(records).count <= ReplicationProtocol.maximumBatchBytes+1024 else {throw ReplicationError.bounds}
        var pending:[String:Data]=[:],newLegacy=0
        for record in records {
            let op=record.operation, entry=try InventoryEntry(op), raw=try CanonicalJSON.encode(record)
            if let existing=try await repository.load(ReplicationRecord.self,key:stageKey(op.id)), existing != record {throw ReplicationError.contentCollision}
            switch record {
            case .legacy:
                guard let root=authorization.genesis.body.roots.first(where:{$0.deviceId==op.operation.deviceId}),op.verified(by:root) else {throw ReplicationError.unauthorized}
                if legacySealed {
                    guard try await repository.load(String.self,key:legacyKey(op.id))==entry.contentDigest else {throw ReplicationError.unauthorized}
                    continue
                }
                let key=legacyKey(op.id)
                if let prior=try await repository.load(String.self,key:key){guard prior==entry.contentDigest else{throw ReplicationError.contentCollision}}
                else if pending[key]==nil{newLegacy+=1}
                pending[legacyKey(op.id)]=try CanonicalJSON.encode(entry.contentDigest)
            case .authorized(let value):
                _ = try value.verify(in:authorization)
                if let prior=try await repository.load(AuthorizedOperation.self,key:proofKey(op.id)) {
                    guard prior==value else {throw ReplicationError.contentCollision};continue
                }
                let key=sequenceKey(value.body)
                if let prior = pending[key] {
                    guard try CanonicalJSON.decode(UUID.self,from:prior)==op.id else {throw ReplicationError.authorizationFork}
                }
                if let prior=try await repository.load(UUID.self,key:key),prior != op.id {throw ReplicationError.authorizationFork}
                pending[key]=try CanonicalJSON.encode(op.id)
            }
            if let prior=pending[stageKey(op.id)],prior != raw {throw ReplicationError.contentCollision}
            pending[stageKey(op.id)]=raw
        }
        if newLegacy>0{
            let count=try await readLegacyCount()+newLegacy
            guard count<=authorization.genesis.body.legacyCheckpoint.count else{throw ReplicationError.contentCollision}
            pending[prefix+"legacy-count"]=try CanonicalJSON.encode(count)
        }
        try await repository.saveAtomically(pending)
        if newLegacy>0{legacyCount=(legacyCount ?? 0)+newLegacy}
        try await sealLegacyIfComplete();try await promote()
    }
    private func sealLegacyIfComplete() async throws {
        guard !legacySealed else{return}
        let expected=authorization.genesis.body.legacyCheckpoint.count
        let known=try await readLegacyCount()
        guard known<=expected else{throw ReplicationError.contentCollision}
        guard known==expected else{return}
        var cursor:String?,count=0,hash=SHA256()
        hash.update(data:Data("Together-Inventory-4\n".utf8))
        repeat {
            let rows=try await repository.localPage(prefix:prefix+"legacy/",after:cursor,limit:256)
            for row in rows {
                guard let id=UUID(uuidString:String(row.id.suffix(36))) else {throw ReplicationError.invalidPage}
                let entry=InventoryEntry(operationId:id,contentDigest:try CanonicalJSON.decode(String.self,from:row.bytes))
                hash.update(data:ReplicationHash.inventoryLine(entry));count+=1
            }
            cursor=rows.count==256 ? rows.last?.id:nil
        } while cursor != nil
        let wanted=authorization.genesis.body.legacyCheckpoint
        guard count<=wanted.count else {throw ReplicationError.contentCollision}
        guard count==wanted.count else{return}
        guard hash.finalize().map({String(format:"%02x",$0)}).joined()==wanted.digest else {throw ReplicationError.contentCollision}
        cursor=nil
        repeat {
            let rows=try await repository.localPage(prefix:prefix+"legacy/",after:cursor,limit:32)
            var ops:[SignedOperation]=[],remove:[String]=[]
            for row in rows {
                guard let id=UUID(uuidString:String(row.id.suffix(36))) else{throw ReplicationError.invalidPage}
                if let staged=try await repository.load(ReplicationRecord.self,key:stageKey(id)) {
                    ops.append(staged.operation);remove.append(stageKey(id))
                }
            }
            try await repository.commitReplication(ops,records:[:],removing:remove)
            cursor=rows.count==32 ? rows.last?.id:nil
        } while cursor != nil
        try await repository.save(wanted.digest,key:prefix+"legacy-seal");legacySealed=true
    }
    private func readLegacyCount()async throws -> Int{
        if let legacyCount{return legacyCount}
        if let stored=try await repository.load(Int.self,key:prefix+"legacy-count"){legacyCount=stored;return stored}
        var count=0,cursor:String?
        repeat{let rows=try await repository.localPage(prefix:prefix+"legacy/",after:cursor,limit:256);count+=rows.count;cursor=rows.count==256 ? rows.last?.id:nil}while cursor != nil
        legacyCount=count;return count
    }
    private func promote() async throws {
        guard legacySealed else{return}
        for device in authorization.devices.values {
            var head=try await frontier(deviceId:device.id),batch:[AuthorizedOperation]=[]
            if let cutoff=device.revokedAt {
                if head.sequence>=cutoff.sequence {continue}
                var verifyHead=head
                while verifyHead.sequence<cutoff.sequence {
                    guard let record=try await staged(epoch:device.epochId,sequence:verifyHead.sequence+1) else{break}
                    _ = try record.verify(in:authorization)
                    guard record.body.previousDigest==verifyHead.digest else{throw ReplicationError.authorizationFork}
                    verifyHead=try DeviceFrontier(sequence:record.body.sequence,digest:record.digest)
                }
                guard verifyHead.sequence==cutoff.sequence else{continue}
                guard verifyHead==cutoff else{throw ReplicationError.authorizationFork}
            }
            while true {
                if let cutoff=device.revokedAt,head.sequence>=cutoff.sequence{break}
                guard let certified=try await staged(epoch:device.epochId,sequence:head.sequence+1) else{break}
                _ = try certified.verify(in:authorization)
                guard certified.body.previousDigest==head.digest else {throw ReplicationError.authorizationFork}
                head=try DeviceFrontier(sequence:certified.body.sequence,digest:certified.digest);batch.append(certified)
                if batch.count==32 {try await commit(batch,head:head);batch=[]}
            }
            if !batch.isEmpty {try await commit(batch,head:head)}
            // An incomplete revoked prefix remains staged until its signed
            // cutoff head can be verified. No guessed historical permission.
        }
    }
    private func staged(epoch:UUID,sequence:Int64) async throws -> AuthorizedOperation? {
        guard let id=try await repository.load(UUID.self,key:sequenceKey(epoch:epoch,sequence:sequence)),
              let record=try await repository.load(ReplicationRecord.self,key:stageKey(id)),case .authorized(let value)=record else{return nil}
        return value
    }
    private func commit(_ records:[AuthorizedOperation],head:DeviceFrontier) async throws {
        guard let first=records.first else{return}
        var metadata:[String:Data]=[headKey(first.body.epochId):try CanonicalJSON.encode(head)],remove:[String]=[]
        for record in records {metadata[proofKey(record.id)]=try CanonicalJSON.encode(record);remove += [stageKey(record.id),sequenceKey(record.body)]}
        try await repository.commitReplication(records.map(\.body.signedOperation),records:metadata,removing:remove)
    }
    public func append(_ operation:SignedOperation) async throws -> AuthorizedOperation {
        await lock();defer{unlock()};try Task.checkCancellation()
        guard legacySealed,authorization.containsActive(identity.descriptor) else {throw ReplicationError.unauthorized}
        let previous=try await frontier(deviceId:identity.descriptor.deviceId)
        let certified=try AuthorizedOperation.sign(operation,identity:identity,trust:authorization,previous:previous)
        try await commit([certified],head:DeviceFrontier(sequence:certified.body.sequence,digest:certified.digest));return certified
    }
    public func projectionContext() async throws -> ReplicaContext {
        await lock();defer{unlock()};try Task.checkCancellation()
        guard legacySealed else {throw ReplicationError.missingPredecessor}
        var accepted:[UUID:String]=[:],cursor:String?
        repeat {
            let rows=try await repository.operationPage(after:cursor,limit:256)
            for row in rows {
                guard let id=UUID(uuidString:row.id) else {throw ReplicationError.invalidPage}
                let op=try CanonicalJSON.decode(SignedOperation.self,from:row.bytes)
                if let proof=try await repository.load(AuthorizedOperation.self,key:proofKey(id)),(try? proof.verify(in:authorization)) != nil {
                    accepted[id]=try InventoryEntry(op).contentDigest
                } else if try await repository.load(String.self,key:legacyKey(id))==InventoryEntry(op).contentDigest {
                    accepted[id]=try InventoryEntry(op).contentDigest
                }
            }
            cursor=rows.count==256 ? rows.last?.id:nil
        } while cursor != nil
        return try ReplicaContext(local:identity.descriptor,authorization:authorization,acceptedContent:accepted)
    }
    private func lock()async{
        if locked{await withCheckedContinuation{waiters.append($0)}}else{locked=true}
    }
    private func unlock(){if waiters.isEmpty{locked=false}else{waiters.removeFirst().resume()}}
}
