import SwiftUI
import Combine
import TogetherCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
import QuickLook
#endif

/// Presentation-only availability bridges. Business services and signed data do
/// not depend on which branch renders a native control.
extension View {
    func togetherScrollableOnPhone() -> some View { modifier(TogetherPhoneScroll()) }
    func togetherPadding(_ value: CGFloat) -> some View { modifier(TogetherPagePadding(value: value, vertical: true)) }
    func togetherHorizontalPadding(_ value: CGFloat) -> some View { modifier(TogetherPagePadding(value: value, vertical: false)) }
    func togetherForeground(_ color: Color) -> some View { foregroundColor(color) }
    func togetherBackground<S: Shape>(_ color: Color, in shape: S) -> some View { background(shape.fill(color)) }
    @ViewBuilder func togetherMaterialBackground<S: Shape>(in shape: S) -> some View {
        if #available(macOS 12, iOS 15, *) { background(.thinMaterial, in: shape) }
        else { background(shape.fill(TogetherPlatform.surface.opacity(0.96))) }
    }
    @ViewBuilder func togetherMaterialSurface() -> some View {
        if #available(macOS 12, iOS 15, *) { background(.thinMaterial) }
        else { background(TogetherPlatform.surface.opacity(0.96)) }
    }
    @ViewBuilder func togetherLargeControl() -> some View {
        if #available(macOS 13, iOS 17, *) { controlSize(.large) } else { controlSize(.regular) }
    }
    @ViewBuilder func togetherTint(_ color: Color) -> some View {
        if #available(macOS 12, iOS 15, *) { tint(color) }
        else { accentColor(color) }
    }
    @ViewBuilder func togetherAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        if #available(macOS 12, iOS 15, *) { self.animation(animation, value: value) }
        else { self.animation(animation) }
    }
    @ViewBuilder func togetherTextSelection() -> some View {
        if #available(macOS 12, iOS 15, *) { textSelection(.enabled) }
        else { self }
    }
    @ViewBuilder func togetherGroupedForm() -> some View {
        #if os(macOS)
        if #available(macOS 13, *) { formStyle(.grouped) } else { self }
        #else
        self
        #endif
    }
    @ViewBuilder func togetherHideScrollBackground() -> some View {
        if #available(macOS 13, iOS 16, *) { scrollContentBackground(.hidden) } else { self }
    }
    @ViewBuilder func togetherHideScrollIndicators() -> some View {
        if #available(macOS 13, iOS 16, *) { scrollIndicators(.hidden) } else { self }
    }
    @ViewBuilder func togetherScrollTargetLayout() -> some View {
        if #available(macOS 14, iOS 17, *) { scrollTargetLayout() } else { self }
    }
    @ViewBuilder func togetherViewAlignedScrolling() -> some View {
        if #available(macOS 14, iOS 17, *) { scrollTargetBehavior(.viewAligned) } else { self }
    }
    @ViewBuilder func togetherScrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint) -> some View {
        if #available(macOS 14, iOS 17, *) { scrollPosition(id: id, anchor: anchor) } else { self }
    }
    @ViewBuilder func togetherBorderlessMenu() -> some View {
        #if os(macOS)
        menuStyle(BorderlessButtonMenuStyle())
        #else
        self
        #endif
    }
    @ViewBuilder func togetherHideMenuIndicator() -> some View {
        #if os(macOS)
        if #available(macOS 12, *) { menuIndicator(.hidden) } else { self }
        #else
        self
        #endif
    }
    @ViewBuilder func togetherCheckboxToggle() -> some View {
        #if os(macOS)
        toggleStyle(CheckboxToggleStyle())
        #else
        toggleStyle(SwitchToggleStyle())
        #endif
    }
    @ViewBuilder func togetherInteractiveDismissDisabled() -> some View {
        if #available(macOS 12, iOS 15, *) { interactiveDismissDisabled() } else { self }
    }
    @ViewBuilder func togetherProminentButton() -> some View {
        if #available(macOS 12, iOS 15, *) { buttonStyle(.borderedProminent) }
        else { buttonStyle(TogetherLegacyButtonStyle(prominent: true)) }
    }
    @ViewBuilder func togetherBorderedButton() -> some View {
        if #available(macOS 12, iOS 15, *) { buttonStyle(.bordered) }
        else { buttonStyle(TogetherLegacyButtonStyle(prominent: false)) }
    }
    @ViewBuilder func togetherSheetSize(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        frame(maxWidth: width, maxHeight: height)
        #endif
    }
    @ViewBuilder func togetherFocusable() -> some View {
        #if os(macOS)
        focusable()
        #else
        if #available(iOS 17, *) { focusable() } else { self }
        #endif
    }
    @ViewBuilder func togetherOnMove(_ action: @escaping (TogetherMoveDirection) -> Void) -> some View {
        #if os(macOS)
        onMoveCommand { direction in
            switch direction { case .up: action(.up); case .down: action(.down); default: action(.other) }
        }
        #else
        self
        #endif
    }
    @ViewBuilder func togetherHideListSeparator() -> some View {
        if #available(macOS 13, iOS 15, *) { listRowSeparator(.hidden) } else { self }
    }
    func togetherConfirmation(_ title: String, isPresented: Binding<Bool>, confirmationTitle: String,
                              message: String? = nil, identifier: String = "confirmation.accept", action: @escaping () -> Void) -> some View {
        modifier(TogetherConfirmationModifier(title: title, isPresented: isPresented, confirmationTitle: confirmationTitle,
                                              message: message, identifier: identifier, action: action))
    }
    @ViewBuilder func togetherTask(_ action: @escaping @MainActor () async -> Void) -> some View {
        if #available(macOS 12, iOS 15, *) { task { await action() } }
        else { modifier(TogetherTaskModifier(identity: false, action: action)) }
    }
    @ViewBuilder func togetherTask<ID: Equatable>(id: ID, _ action: @escaping @MainActor () async -> Void) -> some View {
        if #available(macOS 12, iOS 15, *) { task(id: id) { await action() } }
        else { modifier(TogetherTaskModifier(identity: id, action: action)) }
    }
}
enum TogetherMoveDirection { case up, down, other }
private struct TogetherPhoneScroll: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if horizontalSizeClass == .compact { ScrollView { content.frame(maxWidth: .infinity) } }
        else { content }
        #else
        content
        #endif
    }
}
private struct TogetherPagePadding: ViewModifier {
    let value: CGFloat
    let vertical: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        content.padding(.vertical, vertical ? value : 0).padding(.horizontal, horizontalSizeClass == .compact ? 16 : value)
        #else
        if vertical { content.padding(value) } else { content.padding(.horizontal, value) }
        #endif
    }
}
struct TogetherProfileDivider: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @ViewBuilder var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact { Divider() } else { Divider().frame(height: 46) }
        #else
        Divider().frame(height: 46)
        #endif
    }
}
private struct TogetherConfirmationModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let confirmationTitle: String
    let message: String?
    let identifier: String
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 12, iOS 15, *) {
            content.confirmationDialog(title, isPresented: $isPresented) {
                Button(confirmationTitle, role: .destructive, action: action).accessibilityIdentifier(identifier)
                Button(Copy.text("copy.action.2cd0f3be8738"), role: .cancel) { isPresented = false }
            } message: { if let message { Text(message) } }
        } else {
            content.alert(isPresented: $isPresented) {
                Alert(title: Text(title), message: message.map(Text.init),
                      primaryButton: .destructive(Text(confirmationTitle), action: action),
                      secondaryButton: .cancel(Text(Copy.text("copy.action.2cd0f3be8738"))))
            }
        }
    }
}
private struct TogetherTaskModifier<ID: Equatable>: ViewModifier {
    let identity: ID
    let action: @MainActor () async -> Void
    @State private var task: Task<Void, Never>?
    func body(content: Content) -> some View {
        content.onAppear(perform: start).onChange(of: identity) { _ in start() }
            .onDisappear { task?.cancel(); task = nil }
    }
    private func start() { task?.cancel(); task = Task { @MainActor in await action() } }
}
private struct TogetherLegacyButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundColor(prominent ? .white : TogetherTheme.rose)
            .background(RoundedRectangle(cornerRadius: 7).fill(TogetherTheme.rose.opacity(prominent ? 1 : 0.10)))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}
struct TogetherIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }
    var body: some View { Button(action: action) { Label(title, systemImage: TogetherSymbols.name(systemImage)) } }
}
enum TogetherButtonRole { case destructive, cancel }
struct TogetherRoleButton: View {
    let title: String
    let role: TogetherButtonRole
    let action: () -> Void
    init(_ title: String, role: TogetherButtonRole, action: @escaping () -> Void) { self.title = title; self.role = role; self.action = action }
    @ViewBuilder var body: some View {
        if #available(macOS 12, iOS 15, *) { Button(title, role: role == .destructive ? .destructive : .cancel, action: action) }
        else { Button(title, action: action).foregroundColor(role == .destructive ? .red : .primary) }
    }
}
struct TogetherLabeledContent: View {
    let title: String
    let value: String
    init(_ title: String, value: String) { self.title = title; self.value = value }
    @ViewBuilder var body: some View {
        if #available(macOS 13, iOS 16, *) { LabeledContent(title, value: value) }
        else { HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value).foregroundColor(.secondary) } }
    }
}
struct TogetherMultilineField: View {
    let title: String
    @Binding var text: String
    init(_ title: String, text: Binding<String>) { self.title = title; _text = text }
    @ViewBuilder var body: some View {
        if #available(macOS 13, iOS 16, *) { TextField(title, text: $text, axis: .vertical) }
        else {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundColor(.secondary)
                TextEditor(text: $text).frame(minHeight: 72, maxHeight: 130).accessibilityLabel(title)
            }
        }
    }
}
struct TogetherEmptyState: View {
    private let label: AnyView
    private let actions: AnyView
    init(_ title: String, systemImage: String) { label = AnyView(Label(title, systemImage: TogetherSymbols.name(systemImage))); actions = AnyView(EmptyView()) }
    init<L: View, A: View>(@ViewBuilder label: () -> L, @ViewBuilder actions: () -> A) { self.label = AnyView(label()); self.actions = AnyView(actions()) }
    @ViewBuilder var body: some View {
        if #available(macOS 14, iOS 17, *) { ContentUnavailableView { label } actions: { actions } }
        else {
            VStack(spacing: 14) { label.font(.headline).foregroundColor(.secondary); actions }
                .padding(28).frame(maxWidth: .infinity, minHeight: 180)
        }
    }
}
struct TogetherAdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @ViewBuilder var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact { VStack(alignment: .leading, spacing: spacing) { content } }
        else { HStack(spacing: spacing) { content } }
        #else
        HStack(spacing: spacing) { content }
        #endif
    }
}
#if os(macOS)
typealias TogetherPlatformImage = NSImage
#else
typealias TogetherPlatformImage = UIImage
#endif
extension Image {
    init(togetherImage: TogetherPlatformImage) {
        #if os(macOS)
        self.init(nsImage: togetherImage)
        #else
        self.init(uiImage: togetherImage)
        #endif
    }
}
@MainActor enum TogetherPlatform {
    static var giftContentMinimumHeight: CGFloat {
        #if os(macOS)
        330
        #else
        160
        #endif
    }
    static var surface: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    static var becameActive: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }
    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? Copy.text("device.default.name")
        #else
        UIDevice.current.name
        #endif
    }
    static func image(at url: URL) -> TogetherPlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
    static func openOriginal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        TogetherDocumentPreview.shared.open(url)
        #endif
    }
}
#if os(iOS)
@MainActor private final class TogetherDocumentPreview: NSObject, QLPreviewControllerDataSource {
    static let shared = TogetherDocumentPreview()
    private var file: URL?
    func open(_ url: URL) {
        guard let presenter = TogetherFilePanels.presenter() else { return }
        file = url
        let preview = QLPreviewController(); preview.dataSource = self
        presenter.present(preview, animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { file == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { file! as NSURL }
}
#endif

/// Symbols are OS resources, not bundled artwork. Preserve the intended symbol
/// when present and choose a semantic older-system equivalent when absent.
@MainActor enum TogetherSymbols {
    private static var resolved: [String: String] = [:]
    static func name(_ requested: String) -> String {
        if let cached = resolved[requested] { return cached }
        #if os(macOS)
        let exists = NSImage(systemSymbolName: requested, accessibilityDescription: nil) != nil
        #else
        let exists = UIImage(systemName: requested) != nil
        #endif
        let fallbacks = ["checklist": "checkmark.square", "point.3.connected.trianglepath.dotted": "link",
                         "calendar.badge.clock": "calendar", "calendar.badge.exclamationmark": "calendar",
                         "envelope.badge.fill": "envelope.fill", "list.bullet.rectangle": "list.bullet",
                         "globe.badge.checkmark": "globe", "person.crop.circle.badge.checkmark": "person.crop.circle",
                         "network": "link", "externaldrive.badge.checkmark": "externaldrive"]
        let value = exists ? requested : fallbacks[requested] ?? "circle"
        resolved[requested] = value
        return value
    }
}
