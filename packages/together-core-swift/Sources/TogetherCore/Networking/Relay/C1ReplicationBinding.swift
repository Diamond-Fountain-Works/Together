import Foundation

public struct C1ReplicationBinding: Codable, Equatable, Sendable {
  public var serviceURL: URL
  public var spaceId: UUID
  public var legacyRouteId: UUID
  public var localDeviceId: UUID
  public init(serviceURL: URL, spaceId: UUID, legacyRouteId: UUID, localDeviceId: UUID) {
    self.serviceURL = serviceURL
    self.spaceId = spaceId
    self.legacyRouteId = legacyRouteId
    self.localDeviceId = localDeviceId
  }
}
