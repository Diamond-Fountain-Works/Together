import Foundation

extension ReplicaEngine {
    @discardableResult public func grant(fulfiller: UUID, beneficiary: UUID, quantity: Int, date: CivilDate, notes: String) throws -> UUID {
        let id = UUID()
        try append(entity: id, type: .wishGrant, action: .create, fields: ["spaceId": .id(context.spaceId), "fulfillerId": .id(fulfiller), "beneficiaryId": .id(beneficiary), "quantity": .integer(quantity), "grantedOn": .string(date.iso), "createdBy": .id(identity.descriptor.userId), "notes": .string(notes)])
        return id
    }
    public func adjustGrant(_ grantId: UUID, delta: Int, notes: String) throws {
        try append(entity: UUID(), type: .grantAdjustment, action: .create, fields: ["grantId": .id(grantId), "delta": .integer(delta), "notes": .string(notes)])
    }
    @discardableResult public func createWish(grantId: UUID, title: String, description: String) throws -> UUID {
        let id = UUID()
        try append(entity: id, type: .wishItem, action: .create, fields: ["grantId": .id(grantId), "title": .string(title), "description": .string(description), "createdBy": .id(identity.descriptor.userId)])
        return id
    }
    public func requestFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .requestFulfillment, fields: [:]) }
    public func confirmFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .confirmFulfillment, fields: [:]) }
    public func rejectFulfillment(_ id: UUID) throws { try append(entity: id, type: .wishItem, action: .rejectFulfillment, fields: [:]) }

}
