import Foundation
import TogetherCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Native file UI only. Original files are copied by MediaStore's verified
/// export boundary; no image resizing or format conversion happens here.
@MainActor enum TogetherFilePanels {
    static func choose(types: [UTType], directory: URL? = nil) async throws -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return try await TogetherDocumentPicker.shared.choose(types: types)
        #endif
    }
    static func confirm(title: String, message: String, action: String) async -> Bool {
        #if os(macOS)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: action); alert.addButton(withTitle: Copy.text("copy.action.2cd0f3be8738"))
        return alert.runModal() == .alertFirstButtonReturn
        #else
        guard let presenter = presenter() else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: action, style: .default) { _ in continuation.resume(returning: true) })
            alert.addAction(UIAlertAction(title: Copy.text("copy.action.2cd0f3be8738"), style: .cancel) { _ in continuation.resume(returning: false) })
            presenter.present(alert, animated: true)
        }
        #endif
    }
    static func exportJSON(_ data: Data, filename: String, directory: URL? = nil) async throws {
        #if os(macOS)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = filename
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
        #else
        let staging = try temporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        let file = staging.appendingPathComponent((filename as NSString).lastPathComponent)
        try data.write(to: file, options: .atomic)
        try await TogetherDocumentPicker.shared.export(file)
        #endif
    }
    static func exportOriginal(_ asset: MediaAsset, store: MediaStore, directory: URL? = nil) async throws {
        let filename = (asset.originalFilename as NSString).lastPathComponent
        #if os(macOS)
        let panel = NSSavePanel(); panel.nameFieldStringValue = filename; panel.directoryURL = directory
        if let type = UTType(filenameExtension: asset.fileExtension) { panel.allowedContentTypes = [type] }
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let access = target.startAccessingSecurityScopedResource(); defer { if access { target.stopAccessingSecurityScopedResource() } }
        try await Task.detached { try store.exportOriginal(asset, to: target) }.value
        #else
        let staging = try temporaryExportDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        let file = staging.appendingPathComponent(filename)
        try await Task.detached { try store.exportOriginal(asset, to: file) }.value
        try await TogetherDocumentPicker.shared.export(file)
        #endif
    }
    #if os(iOS)
    static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap(\.windows)
        guard var value = windows.first(where: \.isKeyWindow)?.rootViewController ?? windows.first?.rootViewController else { return nil }
        while let next = value.presentedViewController, !next.isBeingDismissed { value = next }
        return value.isBeingDismissed ? nil : value
    }
    private static func temporaryExportDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    #endif
}
#if os(iOS)
@MainActor private final class TogetherDocumentPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = TogetherDocumentPicker()
    private var continuation: CheckedContinuation<[URL]?, any Error>?
    func choose(types: [UTType]) async throws -> URL? {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        return try await present(picker)?.first
    }
    func export(_ file: URL) async throws {
        _ = try await present(UIDocumentPickerViewController(forExporting: [file], asCopy: true))
    }
    private func present(_ picker: UIDocumentPickerViewController) async throws -> [URL]? {
        guard continuation == nil, let presenter = TogetherFilePanels.presenter() else {
            throw TogetherError.invalid(Copy.text("presentation.error.retry"))
        }
        picker.allowsMultipleSelection = false; picker.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presenter.present(picker, animated: true)
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(controller, urls: urls) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(controller, urls: nil) }
    private func finish(_ controller: UIDocumentPickerViewController, urls: [URL]?) {
        guard let continuation else { return }; self.continuation = nil
        controller.dismiss(animated: true) { continuation.resume(returning: urls) }
    }
}
#endif
