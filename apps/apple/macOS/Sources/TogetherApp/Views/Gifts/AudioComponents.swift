import SwiftUI
import TogetherCore
@preconcurrency import AVFoundation

@MainActor @Observable final class VoiceRecorder {
    var recording = false
    var paused = false
    var starting = false
    var url: URL?
    var error: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var startToken: UUID?
    func start() async {
        guard !starting, !recording else { return }
        starting = true; error = nil; defer { starting = false }
        let token = UUID(); startToken = token
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { error = Copy.text("copy.guidance.4673175cd9f2"); return }
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard startToken == token else { return }
        guard granted else { error = Copy.text("copy.guidance.8cbde1ab6315"); return }
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Together-voice-\(UUID()).m4a")
            recorder = try AVAudioRecorder(url: file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            guard recorder?.prepareToRecord() == true, recorder?.record() == true else { throw TogetherError.invalid(Copy.text("copy.error.5ef4f050153c")) }
            url = file; recording = true; paused = false
        } catch { self.error = error.localizedDescription }
    }
    func togglePause() { if paused { paused = recorder?.record() != true } else { recorder?.pause(); paused = true } }
    func stop() -> URL? { recorder?.stop(); recorder = nil; recording = false; paused = false; return url }
    func discard() { startToken = nil; recorder?.stop(); recorder = nil; recording = false; paused = false; if let url { try? FileManager.default.removeItem(at: url) }; url = nil }
}

@MainActor @Observable private final class AudioPlayback {
    var playing = false
    var elapsed: Double = 0
    var duration: Double = 0
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var update: Task<Void, Never>?
    func prepare(_ url: URL) {
        stop()
        error = nil
        do {
            player = try AVAudioPlayer(contentsOf: url); duration = player?.duration ?? 0
            guard duration.isFinite, duration >= 0 else { throw TogetherError.invalid(Copy.text("copy.error.d0eefe11ae2b")) }
            player?.prepareToPlay()
        }
        catch { self.error = Copy.format("copy.guidance.0bade33ffdbe", String(describing: error.localizedDescription)) }
    }
    func toggle() {
        guard let player else { return }
        if playing { player.pause(); playing = false; update?.cancel() }
        else {
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.play() else { error = Copy.text("copy.status.76137a92a3f3"); return }; playing = true
            update = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
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
    @State private var playback = AudioPlayback()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(playback.playing ? Copy.text("copy.action.858e4ba7a29f") : Copy.text("copy.action.436e61016e26"), systemImage: playback.playing ? "pause.fill" : "play.fill") { playback.toggle() }.disabled(playback.error != nil).accessibilityIdentifier("audio.playPause")
                Slider(value: Binding(get: { min(playback.elapsed, playback.duration) }, set: { playback.seek($0) }), in: 0...max(0.1, playback.duration)).accessibilityLabel(Copy.text("copy.status.584fc5fc5dce"))
                Text(Copy.format("copy.guidance.f7fe73b265ee", String(describing: time(playback.elapsed)), String(describing: time(playback.duration)))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let error = playback.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .onAppear { playback.prepare(url) }.onChange(of: url) { _, url in playback.prepare(url) }.onDisappear { playback.stop() }
    }
    private func time(_ seconds: Double) -> String { guard seconds.isFinite else { return "0:00" }; let s = Int(min(Double(Int.max / 2), max(0, seconds))); return String(format: "%d:%02d", s / 60, s % 60) }
}
