import Foundation

/// Callback adapters keep macOS 11 on the same authenticated protocol without
/// depending on Foundation's macOS 12 async networking entry points.
enum CompatibilityURLSession {
    static func receive(_ task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { continuation in
            task.receive { continuation.resume(with: $0) }
        }
    }
    static func send(_ message: URLSessionWebSocketTask.Message, through task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.send(message) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    static func boundedData(for request: URLRequest, session: URLSession, maximum: Int) async throws -> (Data, URLResponse) {
        guard maximum > 0, maximum <= FrameDecoder.maximum else { throw ReplicationError.bounds }
        let collector = BoundedResponseCollector(maximum: maximum)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { collector.start(request: request, configuration: session.configuration, continuation: $0) }
        } onCancel: { collector.cancel() }
    }
}

/// This deliberately uses a data delegate, not the completion-handler dataTask
/// API: the latter buffers an unbounded response before the app can reject it.
private final class BoundedResponseCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximum: Int
    private let lock = NSLock()
    private var completed = false
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var bytes = Data()
    init(maximum: Int) { self.maximum = maximum }

    func start(request: URLRequest, configuration: URLSessionConfiguration, continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
        let installed = lock.withLock {
            guard !completed else { return false }
            self.continuation = continuation; return true
        }
        guard installed else { continuation.resume(throwing: CancellationError()); return }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        let active = lock.withLock {
            guard !completed else { return false }
            self.session = session; self.task = task; return true
        }
        if active { task.resume() } else { session.invalidateAndCancel() }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(Data, URLResponse), any Error>) {
        let pending: (CheckedContinuation<(Data, URLResponse), any Error>?, URLSession?) = lock.withLock {
            guard !completed else { return (nil, nil) }
            completed = true
            let pending = (continuation, session)
            continuation = nil; session = nil; task = nil; bytes = Data()
            return pending
        }
        pending.0?.resume(with: result)
        pending.1?.invalidateAndCancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Signed headers must never follow redirects to another origin.
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(maximum) else {
            completionHandler(.cancel)
            finish(.failure(TogetherError.invalid(Copy.text("copy.error.6ec90dcd380a"))))
            return
        }
        let active = lock.withLock {
            guard !completed else { return false }
            self.response = response; return true
        }
        completionHandler(active ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = lock.withLock {
            guard !completed else { return false }
            guard data.count <= maximum - bytes.count else { return true }
            bytes.append(data); return false
        }
        if overflow { finish(.failure(TogetherError.invalid(Copy.text("copy.error.6ec90dcd380a")))) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)); return }
        let result: Result<(Data, URLResponse), any Error> = lock.withLock {
            guard let response else { return .failure(URLError(.badServerResponse)) }
            return .success((bytes, response))
        }
        finish(result)
    }
}
