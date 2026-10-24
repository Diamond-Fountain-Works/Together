import Foundation
import Testing
@testable import TogetherCore

@Suite("Back-deployed timing and bounded networking") struct CompatibilityRuntimeTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompatibilityHTTPProtocol.self]
        return URLSession(configuration: configuration)
    }
    @Test func continuousElapsedTimeAndCancellationDoNotUseWallClock() async throws {
        let before = CompatibilityClock.now
        try await CompatibilityClock.sleep(for: .milliseconds(3))
        let after = CompatibilityClock.now
        #expect(after > before && before.duration(to: after) >= .milliseconds(1))
        #expect(before.advanced(by: .milliseconds(10)).duration(to: before) < .milliseconds(0))
        let waiting = Task { try await CompatibilityClock.sleep(for: .seconds(30)) }
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
    }
    @Test func durationComponentsAndOutOfRangeInputsCannotOverflow() {
        let maximum = CompatibilityDuration.seconds(Int64.max)
        #expect(maximum.components.seconds == Int64.max / 1_000_000_000)
        #expect(CompatibilityDuration.seconds(UInt64.max) == maximum)
        #expect(CompatibilityDuration.seconds(Double.infinity) == maximum)
        #expect(CompatibilityDuration.seconds(Double.nan) == .zero)
        let negative = CompatibilityDuration.milliseconds(-1500).components
        #expect(negative.seconds == -1 && negative.attoseconds == -500_000_000_000_000_000)
    }
    @Test func callbackNetworkPreservesExactBytesAndBoundsAdvertisedAndStreamedBodies() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let (bytes, response) = try await CompatibilityURLSession.boundedData(for: URLRequest(url: URL(string: "https://synthetic.invalid/ok")!), session: session, maximum: 8)
        #expect(bytes == Data("onetwo".utf8) && (response as? HTTPURLResponse)?.statusCode == 200)
        for path in ["header-too-large", "stream-too-large"] {
            await #expect(throws: (any Error).self) {
                try await CompatibilityURLSession.boundedData(for: URLRequest(url: URL(string: "https://synthetic.invalid/" + path)!), session: session, maximum: 8)
            }
        }
        await #expect(throws: ReplicationError.bounds) {
            try await CompatibilityURLSession.boundedData(for: URLRequest(url: URL(string: "https://synthetic.invalid/ok")!), session: session, maximum: 0)
        }
    }
    @Test func callbackCancellationFinishesWithoutWaitingForServer() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let task = Task {
            try await CompatibilityURLSession.boundedData(for: URLRequest(url: URL(string: "https://synthetic.invalid/wait")!), session: session, maximum: 8)
        }
        for _ in 0..<100 where !CompatibilityHTTPProtocol.waitStarted.isSet { try await CompatibilityClock.sleep(for: .milliseconds(1)) }
        #expect(CompatibilityHTTPProtocol.waitStarted.isSet)
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

private final class CompatibilityFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
private final class CompatibilityHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let waitStarted = CompatibilityFlag()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.path == "/wait" { Self.waitStarted.set(); return }
        let headers = request.url!.path == "/header-too-large" ? ["Content-Length": "1000000"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.url!.path == "/stream-too-large" {
            client?.urlProtocol(self, didLoad: Data("123456".utf8))
            client?.urlProtocol(self, didLoad: Data("789012".utf8))
        } else { client?.urlProtocol(self, didLoad: Data("onetwo".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
