import Foundation

/// Transport bounds do not limit original media: existing media chunks are
/// separate bounded frames, never one file-sized allocation.
public enum P2PTransportLimits {
    public static let maximumFrameBytes = 524_288
    public static let alpn = Data("together/p4/1".utf8)
    /// Normal QA App uses the existing C1 replication/media content envelope.
    /// The earlier CLI raw-ReplicationFrame protocol remains unchanged.
    public static let nativeAppALPN = Data("together/p4/c1-content/1".utf8)
}
