import SwiftUI
import TogetherCore
import AppKit

private struct TogetherMotionOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    var togetherMotionOverride: Bool? {
        get { self[TogetherMotionOverrideKey.self] }
        set { self[TogetherMotionOverrideKey.self] = newValue }
    }
}
@propertyWrapper struct TogetherMotionPreference: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.togetherMotionOverride) private var testOverride
    var wrappedValue: Bool { testOverride ?? system }
}

enum TogetherTheme {
    static let rose = Color(red: 0.77, green: 0.40, blue: 0.47)
    static let ivory = Color(red: 0.985, green: 0.968, blue: 0.943)
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.105, green: 0.095, blue: 0.10) : ivory }
    static func quickMotion(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: 0.18) }
    static func standardMotion(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(response: 0.28, dampingFraction: 0.9) }
    static func expressiveMotion(_ reduce: Bool) -> Animation? { reduce ? nil : .spring(response: 0.42, dampingFraction: 0.86) }
    static func motion(_ reduce: Bool) -> Animation? { standardMotion(reduce) }
}
struct TogetherCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.055), lineWidth: 1))
    }
}
struct AvatarView: View {
    let profile: UserProfile?
    var size: CGFloat = 52
    var engine: ReplicaEngine? = nil
    @State private var originalPreview: NSImage?
    var body: some View {
        Group {
            if let originalPreview { Image(nsImage: originalPreview).resizable().scaledToFill() }
            else if let data = profile?.avatarData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    LinearGradient(colors: [TogetherTheme.rose.opacity(0.25), TogetherTheme.ivory.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "person.fill").foregroundStyle(TogetherTheme.rose.opacity(0.7)).font(.system(size: size * 0.38))
                }
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .accessibilityLabel(profile?.displayName ?? Copy.text("copy.guidance.0a1bb44784ae"))
        .task(id: "\(profile?.avatarAssetId?.uuidString ?? "none"):\(profile?.avatarCrop?.descriptionKey ?? "center"):\(profile?.avatarAssetId.flatMap { engine?.mediaProgress[$0]?.status.rawValue } ?? "idle")") {
            guard let id = profile?.avatarAssetId else { originalPreview = nil; return }
            guard let engine, let asset = engine.snapshot.mediaAssets[id], engine.mediaStore.hasVerified(asset) else { return }
            let store = engine.mediaStore, crop = profile?.avatarCrop
            if let url = try? await Task.detached(operation: { try store.thumbnail(asset, crop: crop) }).value { originalPreview = NSImage(contentsOf: url) }
        }
    }
}
struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 30, weight: .semibold, design: .rounded)); if !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.secondary) } } }
}
private extension AvatarCrop { var descriptionKey: String { "\(zoom):\(horizontal):\(vertical)" } }
