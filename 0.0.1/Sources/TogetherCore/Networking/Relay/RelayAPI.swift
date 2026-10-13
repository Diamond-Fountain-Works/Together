import Foundation
import CryptoKit

public struct RelayBinding: Codable, Equatable, Sendable {
    public var serviceURL: URL
    public var routeId: UUID
    public var peerDeviceId: UUID
    public var peerPublicKey: Data
    public var localDeviceId: UUID
}
struct RelayMember: Codable, Sendable { var descriptor: DeviceDescriptor; var profileName: String }
struct RelayRoute: Codable, Sendable { var routeId: UUID; var members: [RelayMember]; var expiresAt: Date; var paired: Bool; var revoked: Bool; var confirmed: [UUID] }
struct RelayInvitation: Codable, Sendable { var code: String; var routeId: UUID; var expiresAt: Date }
struct RelayTicket: Codable, Sendable { var ticket: String; var routeId: UUID; var expiresAt: Date }
private struct RelayChallenge: Codable { var id: UUID; var nonce: String; var expiresAt: Date }
private struct RelayIdentityRequest: Codable { var descriptor: DeviceDescriptor; var profileName: String; var expectedPeer: DeviceDescriptor?; var code: String? }
private struct RelayConfirmation: Codable { var transcript: String }
struct RelayAPI {
    let base: URL
    let identity: DeviceIdentity
    let session: URLSession
    init(base: URL, identity: DeviceIdentity, session: URLSession? = nil) throws {
        let local = ["127.0.0.1", "localhost", "::1"].contains(base.host ?? "")
        #if DEBUG
        let allowed = base.scheme == "https" || (base.scheme == "http" && local)
        #else
        let allowed = base.scheme == "https"
        #endif
        guard allowed, base.host?.isEmpty == false, base.path.isEmpty || base.path == "/", base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw TogetherError.invalid(Copy.text("copy.error.183f34eaecaa")) }
        self.base = base; self.identity = identity; self.session = session ?? RelayURLSession.make()
    }
    func createInvitation(name: String, expectedPeer: DeviceDescriptor?) async throws -> RelayInvitation {
        try await request("POST", path: "/v1/invitations", body: CanonicalJSON.encode(RelayIdentityRequest(descriptor: identity.descriptor, profileName: name, expectedPeer: expectedPeer)), as: RelayInvitation.self)
    }
    func join(code: String, name: String) async throws -> RelayRoute {
        try await request("POST", path: "/v1/invitations/join", body: CanonicalJSON.encode(RelayIdentityRequest(descriptor: identity.descriptor, profileName: name, code: code)), as: RelayRoute.self)
    }
    func route(_ id: UUID) async throws -> RelayRoute { try await request("GET", path: "/v1/routes/\(id.uuidString)", as: RelayRoute.self) }
    func ticket(_ id: UUID) async throws -> RelayTicket { try await request("POST", path: "/v1/routes/\(id.uuidString)/ticket", body: Data("{}".utf8), as: RelayTicket.self) }
    func confirm(_ id: UUID, transcript: String) async throws -> RelayRoute { try await request("POST", path: "/v1/routes/\(id.uuidString)/confirm", body: CanonicalJSON.encode(RelayConfirmation(transcript: transcript)), as: RelayRoute.self) }
    func websocketURL(_ id: UUID) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("v1/socket/\(id.uuidString)"), resolvingAgainstBaseURL: false)!
        c.scheme = base.scheme == "https" ? "wss" : "ws"; return c.url!
    }
    private func request<T: Decodable>(_ method: String, path: String, body: Data = Data(), as type: T.Type) async throws -> T {
        let (challengeBytes, response) = try await boundedResponse(URLRequest(url: base.appendingPathComponent("v1/challenge")))
        try check(response, bytes: challengeBytes)
        let challenge = try CanonicalJSON.decode(RelayChallenge.self, from: challengeBytes)
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let text = ["Together-Auth-1", challenge.nonce, method, path, digest, identity.descriptor.deviceId.uuidString].joined(separator: "\n")
        var request = URLRequest(url: base.appendingPathComponent(String(path.dropFirst()))); request.httpMethod = method; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(identity.descriptor.publicKey.base64EncodedString(), forHTTPHeaderField: "X-Together-Key")
        request.setValue(identity.descriptor.deviceId.uuidString, forHTTPHeaderField: "X-Together-Device")
        request.setValue(challenge.id.uuidString, forHTTPHeaderField: "X-Together-Challenge")
        request.setValue(try identity.sign(Data(text.utf8)).base64EncodedString(), forHTTPHeaderField: "X-Together-Signature")
        if method != "GET" { request.httpBody = body }
        let (bytes, result) = try await boundedResponse(request); try check(result, bytes: bytes)
        return try CanonicalJSON.decode(type, from: bytes)
    }
    private func boundedResponse(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (stream, response) = try await session.bytes(for: request)
        var bytes = Data()
        for try await byte in stream {
            guard bytes.count < 16_384 else { throw TogetherError.invalid(Copy.text("copy.error.6ec90dcd380a")) }
            bytes.append(byte)
        }
        return (bytes, response)
    }
    private func check(_ response: URLResponse, bytes: Data) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), bytes.count <= 16_384 else {
            let code = (try? JSONSerialization.jsonObject(with: bytes) as? [String: String])?["error"] ?? "SERVICE_UNAVAILABLE"
            switch code {
            case "RATE_LIMITED": throw TogetherError.invalid(Copy.text("copy.error.4cc53cafce9b"))
            case "INVITATION_UNAVAILABLE": throw TogetherError.invalid(Copy.text("copy.error.d517f113ea56"))
            case "MIGRATION_IDENTITY_MISMATCH", "NOT_A_MEMBER": throw TogetherError.invalid(Copy.text("copy.error.394ef482e899"))
            case "ROUTE_UNAVAILABLE": throw TogetherError.invalid(Copy.text("copy.error.ade4756a0885"))
            default: throw TogetherError.invalid(Copy.text("copy.error.6ec90dcd380a"))
            }
        }
    }
}
