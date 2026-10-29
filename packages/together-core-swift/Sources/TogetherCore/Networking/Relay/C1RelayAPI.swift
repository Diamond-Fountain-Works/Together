import Foundation

struct C1RelaySpace: Codable, Sendable {
  var schemaVersion: Int
  var legacyRouteId: UUID
  var spaceId: UUID
  var archive: AuthorizationArchive
  var authorizationDigest: String
  func verified(local: DeviceDescriptor, previous: SpaceAuthorization?) throws -> SpaceAuthorization
  {
    let trust = try SpaceAuthorization.restore(archive)
    guard schemaVersion == 2, trust.spaceId == spaceId, trust.containsActive(local),
      try trust.digest == authorizationDigest
    else { throw ReplicationError.unauthorized }
    if let previous {
      guard try trust.genesis.digest == previous.genesis.digest,
        previous.events.allSatisfy(trust.events.contains)
      else { throw ReplicationError.staleAuthorization }
    }
    return trust
  }
}
private struct C1Bootstrap: Codable {
  var legacyRouteId: UUID
  var authorization: AuthorizationArchive
}
private struct C1AuthorizationRequest: Codable { var event: SignedDeviceAuthorization }

extension RelayAPI {
  func bootstrap4(legacyRouteId: UUID, authorization: AuthorizationArchive) async throws
    -> C1RelaySpace
  {
    try await request(
      "POST", path: "/v2/spaces",
      body: CanonicalJSON.encode(
        C1Bootstrap(legacyRouteId: legacyRouteId, authorization: authorization)),
      as: C1RelaySpace.self, maximumResponseBytes: 131072)
  }
  func space4(_ space: UUID) async throws -> C1RelaySpace {
    try await request(
      "GET", path: "/v2/spaces/\(space)", as: C1RelaySpace.self, maximumResponseBytes: 131072)
  }
  func authorize4(_ space: UUID, event: SignedDeviceAuthorization) async throws -> C1RelaySpace {
    try await request(
      "POST", path: "/v2/spaces/\(space)/devices",
      body: CanonicalJSON.encode(C1AuthorizationRequest(event: event)), as: C1RelaySpace.self,
      maximumResponseBytes: 131072)
  }
  func ticket4(_ space: UUID) async throws -> RelayTicket {
    try await request(
      "POST", path: "/v2/spaces/\(space)/ticket", body: Data("{}".utf8), as: RelayTicket.self)
  }
  func websocketURL4(_ space: UUID) -> URL {
    var components = URLComponents(
      url: base.appendingPathComponent("v2/socket/\(space)"), resolvingAgainstBaseURL: false)!
    components.scheme = base.scheme == "https" ? "wss" : "ws"
    return components.url!
  }
}
