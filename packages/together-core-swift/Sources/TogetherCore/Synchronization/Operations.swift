import Foundation
import CryptoKit

public enum EntityType: String, Codable, Sendable { case profile, task, recurrenceRule, wishGrant, wishItem, grantAdjustment, sharedSpace, mediaAsset, loveGift, reserveEntry, dateEvent, expense, recurringBill, billRevision, billOccurrence, financeSettings, paymentMethod }
public enum OperationType: String, Codable, Sendable { case create, patch, delete, completeTask, reopenTask, requestFulfillment, confirmFulfillment, rejectFulfillment }
public enum LogValue: Codable, Equatable, Sendable {
    case string(String), integer(Int), date(Date), boolean(Bool), data(Data), null
    public var string: String? { if case let .string(v) = self { v } else { nil } }
    public var integer: Int? { if case let .integer(v) = self { v } else { nil } }
    public var date: Date? { if case let .date(v) = self { v } else { nil } }
    public var bytes: Data? { if case let .data(v) = self { v } else { nil } }
    public var uuid: UUID? { string.flatMap(UUID.init(uuidString:)) }
    public static func id(_ id: UUID?) -> LogValue { id.map { .string($0.uuidString) } ?? .null }
    public static func optionalDate(_ date: Date?) -> LogValue { date.map { .date($0) } ?? .null }
}
public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
            guard milliseconds.isFinite, (-2_208_988_800_000...32_503_680_000_000).contains(milliseconds) else {
                throw EncodingError.invalidValue(date, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Date outside supported 1900–3000 range"))
            }
            try container.encode(Int64(milliseconds))
        }
        return try encoder.encode(value)
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .custom { decoder in
            let milliseconds = try decoder.singleValueContainer().decode(Int64.self)
            guard (-2_208_988_800_000...32_503_680_000_000).contains(milliseconds) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Date outside supported range")
            }
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return try decoder.decode(type, from: data)
    }
}
public struct SyncOperation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { operationId }
    public var operationId: UUID
    public var deviceId: UUID
    public var actorId: UUID
    public var entityId: UUID
    public var entityType: EntityType
    public var operationType: OperationType
    public var lamportClock: Int64
    public var payload: [String: LogValue]
    public var createdAt: Date
    public init(operationId: UUID = UUID(), deviceId: UUID, actorId: UUID, entityId: UUID, entityType: EntityType,
                operationType: OperationType, lamportClock: Int64, payload: [String: LogValue], createdAt: Date = Date()) {
        self.operationId = operationId; self.deviceId = deviceId; self.actorId = actorId; self.entityId = entityId
        self.entityType = entityType; self.operationType = operationType; self.lamportClock = lamportClock
        self.payload = payload; self.createdAt = createdAt
    }
    public var order: OperationOrder { OperationOrder(clock: lamportClock, device: deviceId.uuidString, operation: operationId.uuidString) }
}
public struct OperationOrder: Comparable, Equatable, Sendable {
    public var clock: Int64
    public var device: String
    public var operation: String
    public static func < (a: Self, b: Self) -> Bool {
        if a.clock != b.clock { return a.clock < b.clock }
        if a.device != b.device { return a.device < b.device }
        return a.operation < b.operation
    }
}
public struct SignedOperation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { operation.operationId }
    public var operation: SyncOperation
    public var signature: Data
    public init(operation: SyncOperation, signature: Data) { self.operation = operation; self.signature = signature }
    public func verified(by descriptor: DeviceDescriptor) -> Bool {
        guard operation.deviceId == descriptor.deviceId, operation.actorId == descriptor.userId,
              operation.lamportClock > 0, operation.lamportClock < 9_000_000_000_000_000,
              let bytes = try? CanonicalJSON.encode(operation), bytes.count <= 230_000,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: descriptor.publicKey) else { return false }
        return key.isValidSignature(signature, for: bytes)
    }
}
public enum StableID {
    public static func make(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}
