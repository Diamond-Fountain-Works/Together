import Foundation
import CryptoKit
import Darwin

public enum NetworkAddressPolicy {
    public static func validHost(_ host: String) -> Bool {
        if allowed(host) { return true }
        let name = host.lowercased()
        guard name.count <= 253, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }), !name.hasPrefix("-"), !name.hasSuffix("-") else { return false }
        return name.hasSuffix(".ts.net") || (!name.contains(".") && !name.isEmpty)
    }
    public static func resolve(_ host: String) throws -> String {
        if allowed(host) { return host }
        guard validHost(host) else { throw TogetherError.invalid(Copy.text("copy.error.0f7bf987d382")) }
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM; hints.ai_family = AF_UNSPEC
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { throw TogetherError.invalid(Copy.text("copy.error.44c1b6033067")) }
        defer { freeaddrinfo(first) }
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var addresses: [String] = []
        while let item = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(item.pointee.ai_addr, item.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 { addresses.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
            cursor = item.pointee.ai_next
        }
        guard !addresses.isEmpty, addresses.allSatisfy({ allowed($0) && $0 != "127.0.0.1" && $0 != "::1" }), let address = addresses.first else { throw TogetherError.invalid(Copy.text("copy.error.1c08ba569027")) }
        return address
    }
    public static func localTailscaleAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }; defer { freeifaddrs(first) }
        var item: UnsafeMutablePointer<ifaddrs>? = first
        while let current = item {
            defer { item = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if allowed(value), value != "127.0.0.1", value != "::1" { return value }
            }
        }
        return nil
    }
    public static func allowed(_ host: String) -> Bool {
        if host == "127.0.0.1" || host == "::1" { return true }
        var ipv4 = in_addr(); var ipv6 = in6_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            let p = host.split(separator: ".").compactMap { Int($0) }
            return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
        }
        return inet_pton(AF_INET6, host, &ipv6) == 1 && host.lowercased().hasPrefix("fd7a:115c:a1e0:")
    }
}
struct HandshakeHello: Codable, Equatable, Sendable {
    var descriptor: DeviceDescriptor
    var nonce: UUID
    var profileName: String
    var listenHost: String
    var listenPort: UInt16
    var supportedProtocolVersions: [Int] = [2]
}
public enum ProtocolNegotiation {
    public static let supportedVersions = [2]
    public static func select(remote: [Int]) throws -> Int {
        guard remote.count <= 8, let version = Set(supportedVersions).intersection(remote).max() else { throw TogetherError.invalid(Copy.text("copy.error.eb6f75e7a5e4")) }
        return version
    }
}
enum WirePayload: Codable, Sendable {
    case hello(HandshakeHello), proof, approve, state([UUID]), operation(SignedOperation), finished(String), goodbye
    case mediaRequest(UUID, Int64), mediaChunk(UUID, Int64, Data), mediaComplete(UUID, String), mediaVerified(UUID, String), mediaFailure(UUID, String), giftReceipt(GiftReceipt)
}
struct WireUnsigned: Codable, Sendable {
    var version = 2
    var senderDeviceId: UUID
    var sessionId: String?
    var body: Data
}
struct WireEnvelope: Codable, Sendable {
    var unsigned: WireUnsigned
    var signature: Data
    func verified(publicKey: Data) -> Bool {
        guard unsigned.version == 2, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              let bytes = try? CanonicalJSON.encode(unsigned) else { return false }
        return key.isValidSignature(signature, for: bytes)
    }
}
public struct FrameDecoder: Sendable {
    public static let maximum = 524_288
    private var buffer = Data()
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        guard buffer.count <= Self.maximum + 65_536 else { throw TogetherError.invalid(Copy.text("copy.error.ad7fe3539a96")) }
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0 && length <= Self.maximum else { throw TogetherError.invalid(Copy.text("copy.error.b6b84daef222")) }
            guard buffer.count >= length + 4 else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer.removeFirst(length + 4)
        }
        return frames
    }
    public static func encode(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty && bytes.count <= maximum else { throw TogetherError.invalid(Copy.text("copy.error.4a35195eabf0")) }
        let count = UInt32(bytes.count)
        return Data([UInt8((count >> 24) & 255), UInt8((count >> 16) & 255), UInt8((count >> 8) & 255), UInt8(count & 255)]) + bytes
    }
}
func operationDigest(_ ids: [UUID]) -> String {
    SHA256.hash(data: Data(ids.map(\.uuidString).sorted().joined(separator: ":").utf8)).map { String(format: "%02x", $0) }.joined()
}
