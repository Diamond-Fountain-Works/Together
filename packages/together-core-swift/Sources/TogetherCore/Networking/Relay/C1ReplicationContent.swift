import Foundation

enum C1Content: Codable {
  case replication(ReplicationFrame)
  case media(WirePayload)
  private enum Keys: String, CodingKey { case kind, frame, payload }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(String.self, forKey: .kind) {
    case "replication": self = .replication(try c.decode(ReplicationFrame.self, forKey: .frame))
    case "media": self = .media(try c.decode(WirePayload.self, forKey: .payload))
    default: throw ReplicationError.incompatibleProtocol
    }
  }
  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .replication(let frame):
      try c.encode("replication", forKey: .kind)
      try c.encode(frame, forKey: .frame)
    case .media(let payload):
      try c.encode("media", forKey: .kind)
      try c.encode(payload, forKey: .payload)
    }
  }
}
