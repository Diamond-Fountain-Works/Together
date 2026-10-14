import Foundation

// Display strings are separate from persisted/protocol raw values.
public extension PairingConnectionState {
    var displayName: String {
        switch self {
        case .unpaired: Copy.text("status.connection.unpaired")
        case .waiting: Copy.text("status.connection.waiting")
        case .connected: Copy.text("status.connection.connected")
        case .syncing: Copy.text("status.connection.syncing")
        case .offline: Copy.text("status.connection.offline")
        case .error: Copy.text("status.connection.error")
        }
    }
}
public extension GiftDeliveryState {
    var displayName: String {
        switch self {
        case .local: Copy.text("status.gift.local")
        case .pendingSync: Copy.text("status.gift.pendingSync")
        case .synced: Copy.text("status.gift.synced")
        }
    }
}
public extension MediaTransferStatus {
    var displayName: String {
        switch self {
        case .local: Copy.text("status.media.local")
        case .pending: Copy.text("status.media.pending")
        case .transferring: Copy.text("status.media.transferring")
        case .verified: Copy.text("status.media.verified")
        case .failed: Copy.text("status.media.failed")
        }
    }
}
public extension RecurrenceUnit {
    var displayName: String {
        switch self {
        case .day: Copy.text("status.recurrence.day")
        case .week: Copy.text("status.recurrence.week")
        case .month: Copy.text("status.recurrence.month")
        }
    }
}
