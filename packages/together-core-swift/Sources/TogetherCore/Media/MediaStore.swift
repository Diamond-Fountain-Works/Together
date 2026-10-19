import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import AudioToolbox

/// Immutable URLs and bounded I/O; callers perform imports and final hashing off the UI actor.
public final class MediaStore: Sendable {
    public let root: URL
    public static let chunkSize = 65_536
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "m4a", "aac", "mp3", "wav", "aiff", "aif", "caf", "flac"]
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func originalURL(_ asset: MediaAsset) -> URL { directory(asset.id).appendingPathComponent("original.\(asset.fileExtension)") }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent("assets/\(id.uuidString)", isDirectory: true) }
    private func partialURL(_ asset: MediaAsset) -> URL { directory(asset.id).appendingPathComponent("download.part") }
    private func markerURL(_ asset: MediaAsset) -> URL { directory(asset.id).appendingPathComponent("verified.json") }

    public func importOriginal(from source: URL, type: MediaType, owner: UUID, space: UUID, now: Date) throws -> MediaAsset {
        let ext = source.pathExtension.lowercased()
        guard Self.extensions.contains(ext) else { throw TogetherError.invalid(Copy.text("copy.error.a11b49b139cc")) }
        try validate(source, type: type)
        let bytes = try size(source)
        guard bytes > 0 else { throw TogetherError.invalid(Copy.text("copy.error.ba11f6786c12")) }
        let id = UUID(), dir = directory(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = dir.appendingPathComponent("original.\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let asset = MediaAsset(assetId: id, spaceId: space, ownerId: owner, mediaType: type, originalFilename: String(source.lastPathComponent.prefix(255)), fileExtension: ext, sha256: try digest(target), byteCount: try size(target), createdAt: now)
            try writeMarker(asset)
            if type != .audio { _ = try thumbnail(asset) }
            return asset
        } catch { try? FileManager.default.removeItem(at: dir); throw error }
    }
    public func hasVerified(_ asset: MediaAsset) -> Bool {
        guard let data = try? Data(contentsOf: markerURL(asset)), let marker = try? CanonicalJSON.decode(VerificationMarker.self, from: data),
              marker.sha256 == asset.sha256, marker.byteCount == asset.byteCount,
              let attrs = try? FileManager.default.attributesOfItem(atPath: originalURL(asset).path),
              (attrs[.size] as? NSNumber)?.int64Value == asset.byteCount,
              let modified = attrs[.modificationDate] as? Date else { return false }
        return abs(modified.timeIntervalSince(marker.modifiedAt)) < 0.001
    }
    public func resumeOffset(_ asset: MediaAsset) throws -> Int64 {
        try FileManager.default.createDirectory(at: directory(asset.id), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = partialURL(asset)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw TogetherError.invalid(Copy.text("copy.error.49c38693e018")) }
        }
        let offset = try size(url)
        if offset > asset.byteCount { try FileManager.default.removeItem(at: url); return try resumeOffset(asset) }
        return offset
    }
    public func readChunk(_ asset: MediaAsset, offset: Int64) throws -> Data {
        guard hasVerified(asset), offset >= 0, offset <= asset.byteCount else { throw TogetherError.invalid(Copy.text("copy.error.8082ff966e43")) }
        let file = try FileHandle(forReadingFrom: originalURL(asset)); defer { try? file.close() }
        try file.seek(toOffset: UInt64(offset)); return try file.read(upToCount: Self.chunkSize) ?? Data()
    }
    @discardableResult public func appendChunk(_ bytes: Data, to asset: MediaAsset, offset: Int64) throws -> Int64 {
        guard !bytes.isEmpty, bytes.count <= Self.chunkSize, offset >= 0, offset <= asset.byteCount,
              Int64(bytes.count) <= asset.byteCount - offset else { throw TogetherError.invalid(Copy.text("copy.error.0dba6065a98e")) }
        let current = try resumeOffset(asset)
        if offset < current { return current } // replayed request/chunk after a reconnect
        guard offset == current else { throw TogetherError.invalid(Copy.text("copy.error.d6070f8f98bc")) }
        let file = try FileHandle(forWritingTo: partialURL(asset)); defer { try? file.close() }
        try file.seek(toOffset: UInt64(offset)); try file.write(contentsOf: bytes)
        return offset + Int64(bytes.count)
    }
    public func finishDownload(_ asset: MediaAsset) throws {
        if hasVerified(asset) { return }
        let part = partialURL(asset)
        guard try size(part) == asset.byteCount else { throw TogetherError.invalid(Copy.text("copy.error.fd52798bb6ae")) }
        guard try digest(part) == asset.sha256 else {
            try? FileManager.default.removeItem(at: part)
            throw TogetherError.invalid(Copy.text("copy.error.8d99c018911d"))
        }
        do { try validate(part, type: asset.mediaType) }
        catch { try? FileManager.default.removeItem(at: part); throw error }
        let target = originalURL(asset)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: part, to: target)
        try writeMarker(asset)
        if asset.mediaType != .audio { _ = try thumbnail(asset) }
    }
    public func thumbnail(_ asset: MediaAsset, crop: AvatarCrop? = nil) throws -> URL {
        guard asset.mediaType != .audio, hasVerified(asset) else { throw TogetherError.invalid(Copy.text("copy.error.2791905de686")) }
        let c = crop ?? AvatarCrop()
        guard c.isValid else { throw TogetherError.invalid(Copy.text("copy.error.4a1aecaaf6c6")) }
        let name = "preview-\(String(format: "%.3f-%.3f-%.3f", c.zoom, c.horizontal, c.vertical)).png"
        let target = directory(asset.id).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        guard let source = CGImageSourceCreateWithURL(originalURL(asset) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw TogetherError.invalid(Copy.text("copy.error.b8ab045b7f84")) }
        var display = image
        if asset.mediaType == .avatar {
            let side = Double(min(image.width, image.height)) / c.zoom
            let rect = CGRect(x: Double(image.width) - side, y: Double(image.height) - side, width: side, height: side)
            if let square = image.cropping(to: CGRect(x: rect.origin.x * c.horizontal, y: rect.origin.y * c.vertical, width: side, height: side)) { display = square }
        }
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw TogetherError.invalid(Copy.text("copy.error.6c5330714a37")) }
        CGImageDestinationAddImage(destination, display, nil)
        guard CGImageDestinationFinalize(destination) else { throw TogetherError.invalid(Copy.text("copy.error.5287af4a4345")) }
        return target
    }
    public func containsLocationMetadata(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return p[kCGImagePropertyGPSDictionary] != nil
    }
    public func removeUnpublishedOriginal(_ asset: MediaAsset) throws { try FileManager.default.removeItem(at: directory(asset.id)) }
    public func exportOriginal(_ asset: MediaAsset, to target: URL) throws {
        guard asset.mediaType == .photo, hasVerified(asset) else { throw TogetherError.invalid(Copy.text("copy.error.e2faaefef7e8")) }
        let source = originalURL(asset).standardizedFileURL
        let destination = target.standardizedFileURL
        guard source != destination, !destination.path.hasPrefix(root.standardizedFileURL.path + "/"), destination.pathExtension.lowercased() == asset.fileExtension else { throw TogetherError.invalid(Copy.text("copy.error.98ff4fdf8cf2")) }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".together-export-\(UUID()).\(asset.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: temporary)
        guard try digest(temporary) == asset.sha256 else { throw TogetherError.invalid(Copy.text("copy.error.c5029ed5d755")) }
        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
    public func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hasher = SHA256()
        while let block = try file.read(upToCount: Self.chunkSize), !block.isEmpty { hasher.update(data: block) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func size(_ url: URL) throws -> Int64 { (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0 }
    private func validate(_ url: URL, type: MediaType) throws {
        if type == .audio {
            var file: AudioFileID?
            guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { throw TogetherError.invalid(Copy.text("copy.error.06bc40c441d3")) }
            defer { AudioFileClose(file) }
            var format = AudioStreamBasicDescription(), count = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &count, &format) == noErr, format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { throw TogetherError.invalid(Copy.text("copy.error.7511cf1b701d")) }
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(source) > 0,
                  let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0 > 0,
                  (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0 > 0,
                  CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { throw TogetherError.invalid(Copy.text("copy.error.1bca9cc1647a")) }
        }
    }
    private func writeMarker(_ asset: MediaAsset) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: originalURL(asset).path)
        let marker = VerificationMarker(sha256: asset.sha256, byteCount: asset.byteCount, modifiedAt: attrs[.modificationDate] as? Date ?? .now)
        try CanonicalJSON.encode(marker).write(to: markerURL(asset), options: .atomic)
    }
}
private struct VerificationMarker: Codable { var sha256: String; var byteCount: Int64; var modifiedAt: Date }
