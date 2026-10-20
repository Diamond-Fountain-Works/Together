import Foundation
import IrohLib
import Testing
@testable import TogetherP2P

@Suite("Unverified native incoming connections", .timeLimit(.minutes(1)))
struct UnverifiedIncomingTests {
    @Test func establishedEndpointPinMismatchIsNotClassifiedAsUnauthenticatedNoise() async throws {
        let server = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let client = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        do {
            var address = await server.address()
            address.directAddresses = await server.boundSockets().filter { $0.hasPrefix("127.0.0.1:") }
            let accepted = Task { try await server.accept(expectedEndpointId: String(repeating: "a", count: 64)) }
            let link = try await client.connect(to: address)
            do { try await link.send(Data("synthetic rejected pin".utf8)) } catch { }
            do {
                _ = try await accepted.value
                Issue.record("A mismatched pinned endpoint unexpectedly succeeded")
            } catch P2PTransportError.unexpectedPeer { }
            catch { Issue.record("Pinned identity failure must remain fatal, got \(error)") }
            await link.close()
        } catch { try? await server.close(); try? await client.close(); throw error }
        try await server.close(); try await client.close()
    }
    @Test func rejectedHandshakeDoesNotDestroyListenerOrBypassNextEndpointPin() async throws {
        let server = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let good = try await IrohEndpoint.bind(secretKey: IrohEndpoint.generateTransportKey(), bindAddress: "127.0.0.1:0")
        let wrongALPN = Data("together-unverified-test/1".utf8)
        let bad = try await Endpoint.bind(options: EndpointOptions(preset: presetMinimal(), bindAddr: "127.0.0.1:0",
            secretKey: SecretKey.generate().toBytes(), alpns: [wrongALPN], relayMode: .disabled()))
        do {
            // This is an isolated loopback regression, not public routing QA.
            // Avoid advertising unrelated host IPv6 interfaces to the fixture.
            var address = await server.address()
            address.directAddresses = await server.boundSockets().filter { $0.hasPrefix("127.0.0.1:") }
            #expect(address.directAddresses.count == 1)
            let native = try EndpointAddr(id: EndpointId.fromString(s: address.endpointId), relayUrl: nil, addresses: address.directAddresses)
            print("Synthetic incoming test: bad handshake start")
            let first = Task { try await server.acceptForPartnerBootstrap() }
            do {
                _ = try await bad.connect(addr: native, alpn: wrongALPN)
                Issue.record("Mismatched ALPN unexpectedly connected")
            } catch { print("Synthetic incoming test: client rejected, \(error)") }
            do {
                _ = try await first.value
                Issue.record("Unauthenticated handshake unexpectedly produced a business stream")
            } catch is P2PUnverifiedIncomingError { print("Synthetic incoming test: server rejected pre-authentication candidate") }
            catch { Issue.record("Expected pre-authentication classification, got \(error)") }
            print("Synthetic incoming test: good handshake start")
            let expectedId = await good.address().endpointId
            let accepted = Task { try await server.accept(expectedEndpointId: expectedId) }
            let outgoing = try await good.connect(to: address)
            print("Synthetic incoming test: good handshake connected")
            try await outgoing.send(Data("synthetic verified endpoint".utf8))
            let incoming = try await accepted.value
            #expect(try await incoming.receive() == Data("synthetic verified endpoint".utf8))
            #expect(await incoming.remoteEndpointId() == expectedId)
            await incoming.close(); await outgoing.close()
        } catch {
            try? await bad.close(); try? await server.close(); try? await good.close(); throw error
        }
        try await bad.close(); try await server.close(); try await good.close()
    }
}
