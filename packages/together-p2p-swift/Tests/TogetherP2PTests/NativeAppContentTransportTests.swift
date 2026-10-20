import Foundation
import Testing
import TogetherCore
@testable import TogetherP2P

@Suite("Native App existing C1 content transport", .timeLimit(.minutes(1)))
struct NativeAppContentTransportTests {
    @Test func explicitAppALPNRoundTripRejectsLegacyRawFramePeer() async throws {
        let server = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0",
            applicationProtocol: P2PTransportLimits.nativeAppALPN)
        let modern = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0",
            applicationProtocol: P2PTransportLimits.nativeAppALPN)
        let legacy = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        do {
            var address = await server.address()
            address.directAddresses = await server.boundSockets().filter { $0.hasPrefix("127.0.0.1:") }
            let expected = await modern.address().endpointId
            let accepted = Task {
                for _ in 0..<2 {
                    do { return try await server.accept(expectedEndpointId: expected) }
                    catch is P2PUnverifiedIncomingError { continue }
                }
                throw P2PTransportError.unexpectedPeer
            }
            do {
                let unexpected = try await legacy.connect(to: address)
                await unexpected.close(); Issue.record("Legacy raw-frame ALPN must not negotiate the App's existing C1 content format")
            } catch { }
            let link = try await modern.connect(to: address)
            let frame = try AuthenticatedPeerMediaChannel.encodeReplication(.inventoryStart(UUID()))
            try await link.send(frame)
            let incoming = try await accepted.value
            #expect(try await incoming.receive() == frame)
            try await incoming.send(frame)
            #expect(try await link.receive() == frame)
            #expect(await incoming.remoteEndpointId() == expected)
            await incoming.close(); await link.close()
        } catch {
            try? await server.close(); try? await modern.close(); try? await legacy.close(); throw error
        }
        try await server.close(); try await modern.close(); try await legacy.close()
    }
}
