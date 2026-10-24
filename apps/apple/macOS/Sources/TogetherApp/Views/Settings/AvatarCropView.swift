import SwiftUI
import TogetherCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AvatarCropView: View {
    @ObservedObject var model: ApplicationModel
    var onClose: (() -> Void)? = nil
    @State private var crop = AvatarCrop()
    @State private var preview: TogetherPlatformImage?
    var body: some View {
        VStack(spacing: 20) {
            Text(Copy.text("copy.status.6cd7c4f0f4c3")).font(.title2.weight(.semibold))
            if let preview { Image(togetherImage: preview).resizable().scaledToFill().frame(width: 220, height: 220).clipShape(Circle()) }
            Text(Copy.text("copy.status.e23f8f7eb807")).font(.caption).foregroundColor(.secondary)
            VStack(spacing: 12) {
                HStack { Text(Copy.text("copy.status.b762aec769a3")).frame(width: 46); Slider(value: $crop.zoom, in: 1...4) }
                HStack { Text(Copy.text("copy.status.191e26b5d741")).frame(width: 46); Slider(value: $crop.horizontal, in: 0...1) }
                HStack { Text(Copy.text("copy.status.8284260058dd")).frame(width: 46); Slider(value: $crop.vertical, in: 0...1) }
            }
            HStack {
                Button(Copy.text("copy.action.2cd0f3be8738")) { close() }; Spacer()
                Button(Copy.text("copy.action.bfb466cc16ce")) {
                    model.perform {
                        guard let asset = model.cropAsset else { throw TogetherError.invalid(Copy.text("copy.error.e74585c32e7b")) }
                        try model.engine.setAvatar(assetId: asset.id, crop: crop); close()
                    }
                }.togetherProminentButton().disabled(model.cropAsset == nil)
            }
        }.togetherPadding(26).togetherSheetSize(width: 430).togetherScrollableOnPhone()
        .togetherTask(id: crop) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            guard let asset = model.cropAsset else { return }; let store = model.engine.mediaStore, value = crop
            if let url = try? await Task.detached(operation: { try store.thumbnail(asset, crop: value) }).value, !Task.isCancelled { preview = TogetherPlatform.image(at: url) }
        }
    }
    private func close() {
        if let asset = model.cropAsset { model.perform { try model.engine.discardUnpublishedMedia(asset.id) } }
        if let onClose { onClose() } else { model.dismissSheet() }
    }
}
