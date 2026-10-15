import SwiftUI
import TogetherCore
import AppKit

struct GiftEditorView: View {
    let model: ApplicationModel
    var replyTo: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(Copy.text("copy.emotional.acd76b74d637")).font(.title2.weight(.semibold)); Spacer(); Button(Copy.text("copy.action.3fd47edce45b")) { model.dismissSheet() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("gift.editor.close") }
            ScrollView { GiftComposerView(model: model, replyTo: replyTo) { model.dismissSheet() } }.frame(maxHeight: 520)
        }.padding(28).frame(width: 570)
    }
}
struct GiftComposerView: View {
    let model: ApplicationModel
    var replyTo: UUID?
    var setup = false
    var onFinish: () -> Void
    @State private var draft = LoveGiftDraft()
    @State private var recorder = VoiceRecorder()
    @State private var busy = false
    @State private var sent = false
    @State private var saveError: String?
    private var used: Bool { model.engine.hasSentGift(on: model.currentDate) }
    private var partnerRole: RelationshipLabel { model.engine.partnerProfile?.role ?? .unknown }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LoveCopy.prompt(partner: partnerRole)).font(.headline)
            if used { Text(Copy.text("copy.emotional.a75b098be556")).foregroundStyle(TogetherTheme.rose) }
            ZStack(alignment: .topLeading) {
                if draft.text.isEmpty { Text(Copy.text("copy.status.2c30c0227788")).foregroundStyle(.tertiary).padding(.horizontal, 8).padding(.vertical, 10).allowsHitTesting(false) }
                TextEditor(text: $draft.text).accessibilityIdentifier("gift.textInput").font(.body).scrollContentBackground(.hidden).padding(3).frame(minHeight: 100, maxHeight: 150)
                    .onChange(of: draft.text) { _, text in if text.count > LoveGiftDraft.maximumCharacters { draft.text = String(text.prefix(LoveGiftDraft.maximumCharacters)) } }
            }.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Menu {
                    Button(Copy.text("copy.action.e37fc2d39902")) { Task { await recorder.start() } }.disabled(recorder.recording || recorder.starting || busy)
                    Button(Copy.text("copy.action.4b5e4c962305")) { importAttachment(.audio) }
                } label: { Label(Copy.text("copy.status.43974b287b93"), systemImage: "mic") }
                Button(Copy.text("copy.action.5edc672292ef"), systemImage: "photo") { importAttachment(.photo) }
                Spacer(); Text(Copy.format("copy.status.2afb58834f9b", String(describing: draft.text.count))).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }.disabled(busy)
            if recorder.recording {
                HStack {
                    Label(recorder.paused ? Copy.text("copy.status.598133b569df") : Copy.text("copy.status.5254d30be60f"), systemImage: "mic.fill").foregroundStyle(TogetherTheme.rose)
                    Spacer(); Button(recorder.paused ? Copy.text("copy.action.7c9691192f1b") : Copy.text("copy.action.8d12fc0d4eb2")) { recorder.togglePause() }
                    Button(Copy.text("copy.action.dcf59b082865")) { if let url = recorder.stop() { attach(url, type: .audio, temporary: true) } }
                    Button(Copy.text("copy.action.2cd0f3be8738")) { recorder.discard() }
                }
            }
            if let id = draft.audioAssetId, let asset = model.engine.mediaAsset(id) {
                HStack { Text(asset.originalFilename).font(.caption).lineLimit(1); Spacer(); Button(Copy.text("copy.action.b7e6276e7f9a"), systemImage: "xmark.circle") { removeAttachment(.audio) }.labelStyle(.iconOnly) }
                AudioPlayerView(url: model.engine.mediaStore.originalURL(asset))
            }
            if let id = draft.photoAssetId, let asset = model.engine.mediaAsset(id) {
                HStack(alignment: .top) {
                    MediaPhotoView(engine: model.engine, asset: asset).frame(maxHeight: 155)
                    Button(Copy.text("copy.action.be99f82cf39f"), systemImage: "xmark.circle") { removeAttachment(.photo) }.labelStyle(.iconOnly)
                }
            }
            if busy { ProgressView(Copy.text("status.media.savingOriginal")).controlSize(.small) }
            if model.engine.context.peer == nil { Text(Copy.text("copy.emotional.3ceeec638ae6")).font(.callout).foregroundStyle(.secondary) }
            Text(Copy.text("copy.status.6a8ae976f27c")).font(.caption).foregroundStyle(.secondary)
            if let error = recorder.error ?? saveError { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button(setup ? Copy.text("copy.action.1e157fdf0388") : Copy.text("copy.action.5329e3f0ee46")) { saveAndFinish() }.disabled(busy || recorder.recording)
                Spacer()
                Button(model.engine.context.peer == nil ? Copy.text("copy.action.14e50ef4f212") : Copy.text("copy.emotional.1a1a433b6d1e")) { send() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(busy || recorder.recording || recorder.starting || sent || !draft.hasContent || (used && model.engine.context.peer != nil)).accessibilityIdentifier("gift.send")
            }
            Text(Copy.format("copy.guidance.c17ea66392d2", String(describing: model.engine.sharedSpace.timeZoneIdentifier))).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { draft = (try? model.engine.draft()) ?? LoveGiftDraft(); if let replyTo { draft.replyToGiftId = replyTo } }
        .onChange(of: draft) { _, value in do { try model.engine.saveDraft(value) } catch { saveError = error.localizedDescription } }
        .onDisappear { recorder.discard() }
    }
    private func importAttachment(_ type: MediaType) { guard let url = model.chooseMedia(type) else { return }; attach(url, type: type) }
    private func attach(_ url: URL, type: MediaType, temporary: Bool = false) {
        busy = true
        Task { @MainActor in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; if temporary { try? FileManager.default.removeItem(at: url) }; busy = false }
            do {
                let asset = try await model.engine.importMedia(from: url, type: type)
                if type == .audio { draft.audioAssetId = asset.id } else { draft.photoAssetId = asset.id }
                try model.engine.saveDraft(draft)
            } catch { saveError = error.localizedDescription }
        }
    }
    private func saveAndFinish() { do { try model.engine.saveDraft(draft); onFinish() } catch { saveError = error.localizedDescription } }
    private func removeAttachment(_ type: MediaType) {
        let id = type == .audio ? draft.audioAssetId : draft.photoAssetId
        if type == .audio { draft.audioAssetId = nil } else { draft.photoAssetId = nil }
        do { try model.engine.saveDraft(draft); if let id { try model.engine.discardUnpublishedMedia(id) } }
        catch { saveError = error.localizedDescription }
    }
    private func send() {
        guard !sent else { return }
        if model.engine.context.peer == nil { saveAndFinish(); return }
        do { _ = try model.engine.sendGift(draft); sent = true; model.lovePulse += 1; onFinish() }
        catch { saveError = error.localizedDescription }
    }
}

struct MediaPhotoView: View {
    let engine: ReplicaEngine
    let asset: MediaAsset
    @State private var preview: NSImage?
    @State private var error: String?
    var body: some View {
        Group {
            if let preview {
                Button { NSWorkspace.shared.open(engine.mediaStore.originalURL(asset)) } label: { Image(nsImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).help(Copy.text("copy.status.74f95c4c0298"))
            } else if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            else { ProgressView(Copy.text("status.media.preview")) }
        }.task(id: asset.id) {
            do { let store = engine.mediaStore; let url = try await Task.detached { try store.thumbnail(asset) }.value; preview = NSImage(contentsOf: url) }
            catch { self.error = error.localizedDescription }
        }
    }
}
