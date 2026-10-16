import Foundation

// Protocol 4 uses explicit tagged objects. These keys are platform contracts,
// independent of Swift enum/SwiftData implementation details. Protocol 3's
// existing SignedOperation / LogValue bytes are deliberately unchanged.
extension ReplicationRecord {
  private enum Keys: String, CodingKey { case kind, legacy, authorized }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(String.self, forKey: .kind) {
    case "legacy": self = .legacy(try c.decode(SignedOperation.self, forKey: .legacy))
    case "authorized":
      self = .authorized(try c.decode(AuthorizedOperation.self, forKey: .authorized))
    default: throw ReplicationError.incompatibleProtocol
    }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .legacy(let value):
      try c.encode("legacy", forKey: .kind)
      try c.encode(value, forKey: .legacy)
    case .authorized(let value):
      try c.encode("authorized", forKey: .kind)
      try c.encode(value, forKey: .authorized)
    }
  }
}
extension ReplicationFrame {
  private enum Keys: String, CodingKey {
    case kind, hintId, passId, requestId, page, cursor, entries, records, checkpoint, receipt
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(String.self, forKey: .kind) {
    case "syncHint": self = .syncHint(try c.decode(UUID.self, forKey: .hintId))
    case "inventoryStart": self = .inventoryStart(try c.decode(UUID.self, forKey: .passId))
    case "inventoryPage":
      self = .inventoryPage(
        try c.decode(UUID.self, forKey: .passId), try c.decode(InventoryPage.self, forKey: .page))
    case "inventoryNext":
      self = .inventoryNext(
        try c.decode(UUID.self, forKey: .passId), try c.decode(UUID.self, forKey: .cursor))
    case "operationRequest":
      self = .operationRequest(
        try c.decode(UUID.self, forKey: .passId), try c.decode(UUID.self, forKey: .requestId),
        try c.decode([InventoryEntry].self, forKey: .entries))
    case "operationBatch":
      self = .operationBatch(
        try c.decode(UUID.self, forKey: .passId), try c.decode(UUID.self, forKey: .requestId),
        try c.decode([ReplicationRecord].self, forKey: .records))
    case "inventoryFinished":
      self = .inventoryFinished(
        try c.decode(UUID.self, forKey: .passId),
        try c.decode(InventoryCheckpoint.self, forKey: .checkpoint))
    case "acknowledgement":
      self = .acknowledgement(try c.decode(SignedAcknowledgement.self, forKey: .receipt))
    default: throw ReplicationError.incompatibleProtocol
    }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .syncHint(let id):
      try c.encode("syncHint", forKey: .kind)
      try c.encode(id, forKey: .hintId)
    case .inventoryStart(let pass):
      try c.encode("inventoryStart", forKey: .kind)
      try c.encode(pass, forKey: .passId)
    case .inventoryPage(let pass, let page):
      try c.encode("inventoryPage", forKey: .kind)
      try c.encode(pass, forKey: .passId)
      try c.encode(page, forKey: .page)
    case .inventoryNext(let pass, let cursor):
      try c.encode("inventoryNext", forKey: .kind)
      try c.encode(pass, forKey: .passId)
      try c.encode(cursor, forKey: .cursor)
    case .operationRequest(let pass, let request, let entries):
      try c.encode("operationRequest", forKey: .kind)
      try c.encode(pass, forKey: .passId)
      try c.encode(request, forKey: .requestId)
      try c.encode(entries, forKey: .entries)
    case .operationBatch(let pass, let request, let records):
      try c.encode("operationBatch", forKey: .kind)
      try c.encode(pass, forKey: .passId)
      try c.encode(request, forKey: .requestId)
      try c.encode(records, forKey: .records)
    case .inventoryFinished(let pass, let checkpoint):
      try c.encode("inventoryFinished", forKey: .kind)
      try c.encode(pass, forKey: .passId)
      try c.encode(checkpoint, forKey: .checkpoint)
    case .acknowledgement(let receipt):
      try c.encode("acknowledgement", forKey: .kind)
      try c.encode(receipt, forKey: .receipt)
    }
  }
}
