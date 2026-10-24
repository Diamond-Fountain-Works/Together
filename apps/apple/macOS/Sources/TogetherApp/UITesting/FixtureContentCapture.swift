#if DEBUG && os(macOS)
import SwiftUI
import AppKit

/// Fallback captures only this app's deterministic fixture view, never the
/// desktop or another app. This is rendering evidence, not an XCUITest result.
struct FixtureContentCapture: NSViewRepresentable {
    let fixture: UIFixture
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        guard ProcessInfo.processInfo.environment["TOGETHER_UI_CAPTURE"] == "1" else { return view }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak view] in
            guard let host = view?.window else { return }
            let window = host.attachedSheet ?? host
            guard let content = window.contentView else { return }
            do {
                content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
                guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw CaptureError.unavailable }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                // Layer-backed AppKit sidebar/chrome cannot be reliably drawn
                // by cacheDisplay. Capture the real financial detail region,
                // or the complete attached sheet, and label that scope honestly.
                var result = bitmap
                if host.attachedSheet == nil, let region = FixtureFinanceRegion.rectangle, let image = bitmap.cgImage {
                    let sx = CGFloat(bitmap.pixelsWide) / content.bounds.width, sy = CGFloat(bitmap.pixelsHigh) / content.bounds.height
                    let area = CGRect(x: region.minX * sx, y: (content.isFlipped ? region.minY : content.bounds.height - region.maxY) * sy, width: region.width * sx, height: region.height * sy).integral.intersection(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
                    guard let cropped = image.cropping(to: area) else { throw CaptureError.unavailable }
                    result = NSBitmapImageRep(cgImage: cropped)
                }
                guard let png = result.representation(using: .png, properties: [:]) else { throw CaptureError.unavailable }
                let filename = fixture.snapshotName + ".png"
                guard filename.range(of: #"^[A-Za-z0-9_-]+\.png$"#, options: .regularExpression) != nil else { throw CaptureError.unavailable }
                try png.write(to: fixture.root.appendingPathComponent(filename), options: .atomic)
                let info: [String: Any] = ["source":"AppKit own fixture content view", "scope":host.attachedSheet == nil ? "financial detail; native sidebar/toolbar excluded" : "presented fixture sheet", "page":fixture.page, "fixtureTime":"2026-10-09T04:00:00Z", "locale":"zh_CN", "dark":fixture.dark, "reduceMotion":fixture.reduceMotion, "windowWidthPoints":host.contentView?.bounds.width ?? 0, "windowHeightPoints":host.contentView?.bounds.height ?? 0, "pixelsWide":result.pixelsWide, "pixelsHigh":result.pixelsHigh]
                try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys, .prettyPrinted]).write(to: fixture.root.appendingPathComponent("capture.json"))
            } catch { try? Data(String(describing: error).utf8).write(to: fixture.root.appendingPathComponent("capture-error.txt")) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private enum CaptureError: Error { case unavailable }
}
@MainActor private enum FixtureFinanceRegion { static var rectangle: CGRect? }
struct FixtureFinanceCaptureAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { RegionView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.needsLayout = true }
    private class RegionView: NSView {
        override func layout() {
            super.layout()
            if let content = window?.contentView { FixtureFinanceRegion.rectangle = convert(bounds, to: content) }
        }
    }
}
#endif
