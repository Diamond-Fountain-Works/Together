import Foundation

public struct AvatarCrop: Codable, Equatable, Hashable, Sendable {
    public var zoom: Double
    public var horizontal: Double
    public var vertical: Double
    public init(zoom: Double = 1, horizontal: Double = 0.5, vertical: Double = 0.5) { self.zoom = zoom; self.horizontal = horizontal; self.vertical = vertical }
    public var isValid: Bool { (1...4).contains(zoom) && (0...1).contains(horizontal) && (0...1).contains(vertical) }
}
public enum MediaType: String, Codable, Sendable { case avatar, photo, audio }
public enum MediaTransferStatus: String, Codable, Sendable { case local, pending, transferring, verified, failed }
public struct MediaAsset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { assetId }
    public var assetId: UUID
    public var spaceId: UUID
    public var ownerId: UUID
    public var mediaType: MediaType
    public var originalFilename: String
    public var fileExtension: String
    public var sha256: String
    public var byteCount: Int64
    public var createdAt: Date
    public var transferStatus: MediaTransferStatus = .pending
    // Derived locally; remote filenames and paths are never used for file operations.
    public var relativeStoragePath: String { "assets/\(assetId.uuidString)/original.\(fileExtension)" }
    public init(assetId: UUID, spaceId: UUID, ownerId: UUID, mediaType: MediaType, originalFilename: String, fileExtension: String, sha256: String, byteCount: Int64, createdAt: Date, transferStatus: MediaTransferStatus = .pending) {
        self.assetId = assetId; self.spaceId = spaceId; self.ownerId = ownerId; self.mediaType = mediaType
        self.originalFilename = originalFilename; self.fileExtension = fileExtension; self.sha256 = sha256; self.byteCount = byteCount; self.createdAt = createdAt; self.transferStatus = transferStatus
    }
    private enum CodingKeys: String, CodingKey { case assetId, spaceId, ownerId, mediaType, originalFilename, fileExtension, sha256, byteCount, createdAt, transferStatus }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assetId = try c.decode(UUID.self, forKey: .assetId); spaceId = try c.decode(UUID.self, forKey: .spaceId); ownerId = try c.decode(UUID.self, forKey: .ownerId)
        mediaType = try c.decode(MediaType.self, forKey: .mediaType); originalFilename = try c.decode(String.self, forKey: .originalFilename)
        fileExtension = try c.decode(String.self, forKey: .fileExtension); sha256 = try c.decode(String.self, forKey: .sha256)
        byteCount = try c.decode(Int64.self, forKey: .byteCount); createdAt = try c.decode(Date.self, forKey: .createdAt)
        transferStatus = (try? c.decode(MediaTransferStatus.self, forKey: .transferStatus)) ?? .pending
    }
}
public struct MediaProgress: Codable, Equatable, Sendable {
    public var assetId: UUID
    public var transferred: Int64
    public var total: Int64
    public var status: MediaTransferStatus
    public var error: String?
    public var fraction: Double { total > 0 ? min(1, Double(transferred) / Double(total)) : 0 }
    public init(assetId: UUID, transferred: Int64, total: Int64, status: MediaTransferStatus, error: String? = nil) {
        self.assetId = assetId; self.transferred = transferred; self.total = total; self.status = status; self.error = error
    }
}
