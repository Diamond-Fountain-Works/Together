import Foundation
import TogetherCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
import PhotosUI
#endif

/// Native file UI only. Original files are copied by MediaStore's verified
/// export boundary; no image resizing or format conversion happens here.
@MainActor enum TogetherFilePanels {
    static func chooseImage(directory: URL? = nil) async throws -> URL? {
        #if os(macOS)
        return try await choose(types: [.image], directory: directory)
        #else
        guard let source = try await TogetherPhotoSourcePicker.shared.choose() else { return nil }
        return source ? try await TogetherPhotoPicker.shared.choose() : try await choose(types: [.image])
        #endif
    }
    static func releaseSelection(_ url: URL) {
        #if os(iOS)
        TogetherPhotoPicker.shared.release(url)
        #endif
    }
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
/// The source prompt owns its dismissal continuation, including iPad outside
/// taps. A dismissed prompt cannot leave the media importer permanently busy.
@MainActor private final class TogetherPhotoSourcePicker: NSObject, UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
    static let shared = TogetherPhotoSourcePicker()
    private var continuation: CheckedContinuation<Bool?, any Error>?
    private var active: UIAlertController?
    private var finishing = false
    func choose() async throws -> Bool? {
        guard continuation == nil, let presenter = TogetherFilePanels.presenter() else {
            throw TogetherError.invalid(Copy.text("presentation.error.retry"))
        }
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        active = menu
        finishing = false
        menu.addAction(UIAlertAction(title: Copy.text("media.action.photoLibrary"), style: .default) { [weak self, weak menu] _ in
            if let menu { self?.finish(menu, value: true) }
        })
        menu.addAction(UIAlertAction(title: Copy.text("media.action.files"), style: .default) { [weak self, weak menu] _ in
            if let menu { self?.finish(menu, value: false) }
        })
        menu.addAction(UIAlertAction(title: Copy.text("copy.action.2cd0f3be8738"), style: .cancel) { [weak self, weak menu] _ in
            if let menu { self?.finish(menu, value: nil) }
        })
        if let popover = menu.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
            popover.delegate = self
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            presenter.present(menu, animated: true) { menu.presentationController?.delegate = self }
        }
    }
    private func finish(_ menu: UIAlertController, value: Bool?) {
        guard active === menu, !finishing else { return }
        finishing = true
        menu.dismiss(animated: true) { self.resolve(menu, value: value) }
    }
    private func resolve(_ menu: UIAlertController, value: Bool?) {
        guard active === menu, let continuation else { return }
        self.continuation = nil
        active = nil
        finishing = false
        continuation.resume(returning: value)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if let menu = presentationController.presentedViewController as? UIAlertController, !finishing { resolve(menu, value: nil) }
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        presentationControllerDidDismiss(popoverPresentationController)
    }
}

/// PHPicker grants access only to the selected representation. Request the
/// current file without decoding/re-encoding UIImage; MediaStore owns the
/// verified original after import. Staging files have a bounded lifetime.
@MainActor private final class TogetherPhotoPicker: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    static let shared = TogetherPhotoPicker()
    private struct Session {
        let id: UUID
        let picker: PHPickerViewController
        let continuation: CheckedContinuation<URL?, any Error>
    }
    private var session: Session?
    private var staged: Set<URL> = []
    func choose() async throws -> URL? {
        guard session == nil, let presenter = TogetherFilePanels.presenter() else {
            throw TogetherError.invalid(Copy.text("presentation.error.retry"))
        }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        return try await withCheckedThrowingContinuation { continuation in
            self.session = Session(id: UUID(), picker: picker, continuation: continuation)
            presenter.present(picker, animated: true) { picker.presentationController?.delegate = self }
        }
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let current = session, current.picker === picker else { return }
        guard let provider = results.first?.itemProvider else { finish(current.id, result: .success(nil)); return }
        let id = current.id
        Task { @MainActor in
            do {
                let file = try await stage(provider)
                guard session?.id == id else {
                    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                    return
                }
                staged.insert(file)
                finish(id, result: .success(file))
            } catch { finish(id, result: .failure(error)) }
        }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let current = session, current.picker === presentationController.presentedViewController else { return }
        session = nil
        current.continuation.resume(returning: nil)
    }
    func release(_ file: URL) {
        guard staged.remove(file) != nil else { return }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
    private func finish(_ id: UUID, result: Result<URL?, any Error>) {
        guard let current = session, current.id == id else {
            if case .success(let file?) = result { release(file) }
            return
        }
        session = nil
        current.picker.dismiss(animated: true) { current.continuation.resume(with: result) }
    }
    private func stage(_ provider: NSItemProvider) async throws -> URL {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            throw TogetherError.invalid(Copy.text("copy.error.1bca9cc1647a"))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-photo-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, error in
                    do {
                        if let error { throw error }
                        guard let source else { throw CocoaError(.fileReadUnknown) }
                        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                        let file = root.appendingPathComponent(source.lastPathComponent)
                        // The provider URL expires when this callback returns.
                        // FileManager copies the file without loading its pixels.
                        try FileManager.default.copyItem(at: source, to: file)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                        continuation.resume(returning: file)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}

@MainActor private final class TogetherDocumentPicker: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    static let shared = TogetherDocumentPicker()
    private var continuation: CheckedContinuation<[URL]?, any Error>?
    private var active: UIDocumentPickerViewController?
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
            self.active = picker
            presenter.present(picker, animated: true) { picker.presentationController?.delegate = self }
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finish(controller, urls: urls) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(controller, urls: nil) }
    private func finish(_ controller: UIDocumentPickerViewController, urls: [URL]?) {
        guard active === controller, let continuation else { return }; self.continuation = nil; active = nil
        controller.dismiss(animated: true) { continuation.resume(returning: urls) }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard active === presentationController.presentedViewController, let continuation else { return }
        self.continuation = nil; active = nil
        continuation.resume(returning: nil)
    }
}
#endif
