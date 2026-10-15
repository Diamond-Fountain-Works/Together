import Foundation

public enum ReplicationStatus: String, Codable, Sendable {
    case localSaved, pendingSync, transferring, remotePersisted, converged, reviewed, domainConfirmed
}
public struct AcknowledgementBody: Codable, Equatable, Sendable {
    public var version = 4
    public var spaceId: UUID
    public var deviceId: UUID
    public var epochId: UUID
    public var entries: [InventoryEntry]
    public var checkpoint: InventoryCheckpoint?
}
public struct SignedAcknowledgement: Codable, Equatable, Sendable {
    public var body: AcknowledgementBody
    public var signature: Data
    public var digest: String { get throws {ReplicationHash.digest(try CanonicalJSON.encode(self))} }
    public func verify(in trust:SpaceAuthorization,from remote:DeviceDescriptor) throws {
        guard body.version==4,body.spaceId==trust.spaceId,body.deviceId==remote.deviceId,
              trust.containsActive(remote),let device=trust.devices[body.deviceId],device.epochId==body.epochId,
              body.entries.count<=ReplicationProtocol.operationBatchSize,body.entries.allSatisfy(\.isValid),
              Set(body.entries.map(\.operationId)).count==body.entries.count,
              body.checkpoint.map({$0.count>=0 && ReplicationHash.valid($0.digest)}) ?? !body.entries.isEmpty,
              body.entries.isEmpty || body.checkpoint==nil,
              SignedSpaceGenesis.verify(signature,bytes:try CanonicalJSON.encode(body),key:remote.publicKey) else{throw ReplicationError.invalidReceipt}
    }
}
public struct AcknowledgedOperation: Codable, Sendable {public var contentDigest:String;public var receiptDigest:String}

public actor DeviceAcknowledgementLedger {
    private let repository:TogetherRepository
    private let index:OperationInventoryIndex
    private let identity:DeviceIdentity
    public init(repository:TogetherRepository,index:OperationInventoryIndex,identity:DeviceIdentity){self.repository=repository;self.index=index;self.identity=identity}
    /// Only called after the receiver's fact transaction and authorization
    /// promotion. Receipt generation itself verifies durable indexed bytes.
    public func receipt(entries:[InventoryEntry],trust:SpaceAuthorization) async throws -> SignedAcknowledgement? {
        guard trust.containsActive(identity.descriptor),let device=trust.devices[identity.descriptor.deviceId],entries.count<=32 else{throw ReplicationError.unauthorized}
        let missing=try await index.missing(entries),absent=Set(missing.map(\.operationId))
        let committed=entries.filter{!absent.contains($0.operationId)}
        guard !committed.isEmpty else{return nil}
        let body=AcknowledgementBody(spaceId:trust.spaceId,deviceId:device.id,epochId:device.epochId,entries:committed.sorted{$0.operationId.uuidString<$1.operationId.uuidString})
        return SignedAcknowledgement(body:body,signature:try identity.sign(CanonicalJSON.encode(body)))
    }
    public func convergenceReceipt(for checkpoint:InventoryCheckpoint,trust:SpaceAuthorization) async throws -> SignedAcknowledgement? {
        guard trust.containsActive(identity.descriptor),let device=trust.devices[identity.descriptor.deviceId] else{throw ReplicationError.unauthorized}
        guard try await index.checkpoint()==checkpoint else{return nil}
        let body=AcknowledgementBody(spaceId:trust.spaceId,deviceId:device.id,epochId:device.epochId,entries:[],checkpoint:checkpoint)
        return SignedAcknowledgement(body:body,signature:try identity.sign(CanonicalJSON.encode(body)))
    }
    @discardableResult public func accept(_ receipt:SignedAcknowledgement,from remote:DeviceDescriptor,trust:SpaceAuthorization) async throws -> Bool {
        try receipt.verify(in:trust,from:remote)
        let proofKey="replication4/ack-proof/"+remote.deviceId.uuidString+"/"+(try receipt.digest)
        if let checkpoint=receipt.body.checkpoint {
            // A concurrent new write makes this complete-set receipt stale.
            // Never infer that the new operation was persisted remotely.
            let frozen=try await index.acquireSnapshot()
            guard frozen.checkpoint==checkpoint else{try await index.releaseSnapshot(frozen);return false}
            do{
                var cursor:UUID?
                repeat {
                    let page=try await index.page(after:cursor,snapshot:frozen)
                    try await persist(receipt,entries:page.entries,proofKey:proofKey)
                    cursor=page.next
                } while cursor != nil
                try await index.releaseSnapshot(frozen)
            }catch{try? await index.releaseSnapshot(frozen);throw error}
            try await repository.save(receipt,key:"replication4/converged/"+remote.deviceId.uuidString)
            return try await index.checkpoint()==checkpoint
        }else{
            guard try await index.missing(receipt.body.entries).isEmpty else{throw ReplicationError.invalidReceipt}
            try await persist(receipt,entries:receipt.body.entries,proofKey:proofKey)
        }
        return true
    }
    private func persist(_ receipt:SignedAcknowledgement,entries:[InventoryEntry],proofKey:String) async throws {
        let digest=try receipt.digest
        var records:[String:Data]=[proofKey:try CanonicalJSON.encode(receipt)]
        for entry in entries {records["replication4/ack/\(receipt.body.deviceId)/\(entry.operationId)"]=try CanonicalJSON.encode(AcknowledgedOperation(contentDigest:entry.contentDigest,receiptDigest:digest))}
        try await repository.saveAtomically(records)
    }
    public func persistedDevices(for entry:InventoryEntry,trust:SpaceAuthorization) async throws -> Set<UUID> {
        var result:Set<UUID>=[]
        for device in trust.activeDevices where device.id != identity.descriptor.deviceId {
            if let saved=try await repository.load(AcknowledgedOperation.self,key:"replication4/ack/\(device.id)/\(entry.operationId)"),saved.contentDigest==entry.contentDigest,
               let proof=try await repository.load(SignedAcknowledgement.self,key:"replication4/ack-proof/\(device.id)/\(saved.receiptDigest)"),
               (try? proof.verify(in:trust,from:device.descriptor)) != nil {result.insert(device.id)}
        };return result
    }
    public func partnerHasPersisted(_ entry:InventoryEntry,trust:SpaceAuthorization) async throws -> Bool {
        let ids=try await persistedDevices(for:entry,trust:trust)
        return ids.contains{trust.devices[$0]?.descriptor.userId != identity.descriptor.userId}
    }
}
