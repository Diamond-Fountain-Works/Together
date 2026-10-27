import Combine
import SwiftUI
import TogetherCore
@preconcurrency import AVFoundation

@MainActor final class VoiceRecorder: ObservableObject {
    @Published var recording = false
    @Published var paused = false
    @Published var starting = false
    @Published var url: URL?
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var startToken: UUID?
    func start() async {
        guard !starting, !recording else { return }
        starting = true; error = nil; defer { starting = false }
        let token = UUID(); startToken = token
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { error = Copy.text("copy.guidance.4673175cd9f2"); return }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await withCheckedContinuation { continuation in AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) } }
        default: granted = false
        }
        guard startToken == token else { return }
        guard granted else { error = Copy.text("copy.guidance.8cbde1ab6315"); return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Together-voice-\(UUID()).m4a")
            recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder?.prepareToRecord() == true, recorder?.record() == true else { throw TogetherError.invalid(Copy.text("copy.error.5ef4f050153c")) }
            url = file; recording = true; paused = false
        } catch { self.error = Copy.userError(error) }
    }
    func togglePause() { if paused { paused = recorder?.record() != true } else { recorder?.pause(); paused = true } }
    func stop() -> URL? { recorder?.stop(); recorder = nil; recording = false; paused = false; return url }
    func discard() { startToken = nil; recorder?.stop(); recorder = nil; recording = false; paused = false; if let url { try? FileManager.default.removeItem(at: url) }; url = nil }
}

@MainActor private final class AudioPlayback: ObservableObject {
    @Published var playing = false
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var update: Task<Void, Never>?
    func prepare(_ url: URL) {
        stop()
        error = nil
        do {
            player = try AVAudioPlayer(contentsOf: url); duration = player?.duration ?? 0
            guard duration.isFinite, duration >= 0 else { throw TogetherError.invalid(Copy.text("copy.error.d0eefe11ae2b")) }
            player?.prepareToPlay()
        }
        catch { self.error = Copy.format("copy.guidance.0bade33ffdbe", String(describing: Copy.userError(error))) }
    }
    func toggle() {
        guard let player else { return }
        if playing { player.pause(); playing = false; update?.cancel() }
        else {
            #if os(iOS)
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { self.error = Copy.userError(error); return }
            #endif
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { error = Copy.text("copy.status.76137a92a3f3"); return }; playing = true
            update = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled, let self, let player = self.player else { return }
                    self.elapsed = player.currentTime.isFinite ? max(0, player.currentTime) : 0
                    if !player.isPlaying { self.playing = false; return }
                }
            }
        }
    }
    func seek(_ value: Double) { player?.currentTime = value; elapsed = value }
    func stop() { player?.stop(); update?.cancel(); update = nil; playing = false; elapsed = 0 }
}
struct AudioPlayerView: View {
    let url: URL
    @StateObject private var playback = AudioPlayback()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TogetherIconButton(playback.playing ? Copy.text("copy.action.858e4ba7a29f") : Copy.text("copy.action.436e61016e26"), systemImage: TogetherSymbols.name(playback.playing ? "pause.fill" : "play.fill")) { playback.toggle() }
                    #if os(iOS)
                    .labelStyle(.iconOnly)
                    #endif
                    .togetherTouchTarget().disabled(playback.error != nil).accessibilityIdentifier("audio.playPause")
                Slider(value: Binding(get: { min(playback.elapsed, playback.duration) }, set: { playback.seek($0) }), in: 0...max(0.1, playback.duration)).accessibilityLabel(Copy.text("copy.status.584fc5fc5dce"))
                #if os(macOS)
                Text(Copy.format("copy.guidance.f7fe73b265ee", String(describing: time(playback.elapsed)), String(describing: time(playback.duration)))).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                #endif
            }
            #if os(iOS)
            Text(Copy.format("copy.guidance.f7fe73b265ee", time(playback.elapsed), time(playback.duration))).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            #endif
            if let error = playback.error { Text(error).font(.caption).foregroundColor(.orange) }
        }.padding(14).togetherMaterialBackground(in: RoundedRectangle(cornerRadius: 12))
            .onAppear { playback.prepare(url) }.onChange(of: url) { url in playback.prepare(url) }.onDisappear { playback.stop() }
    }
    private func time(_ seconds: Double) -> String { guard seconds.isFinite else { return "0:00" }; let s = Int(min(Double(Int.max / 2), max(0, seconds))); return String(format: "%d:%02d", s / 60, s % 60) }
}
