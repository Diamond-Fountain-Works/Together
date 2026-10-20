# Together P2P transport workstream

Separate optional transport package; the production macOS target does not link
this package yet. Existing signed operations, identity and business projection
remain in TogetherCore. No database snapshot replication or cloud business store.

Dependency: official `n0-computer/iroh-ffi` v1.1.0, pinned commit
`5e451092dba0c1a09ee83ff6e5be37b1152a5c58`, MIT/Apache-2.0. The upstream
Package.swift pins its binary checksum. No monitoring service/API key is enabled.

Upstream's published Apple framework supports arm64 macOS 14.5+; existing Together
Universal/macOS 14 support must not be silently removed. Intel/14.0 compatibility
and audited reproducible native builds are release gates before app integration.

`swift test --package-path packages/together-p2p-swift` is the isolated entry point.
Tests do not open production stores or install an app. Direct, relayed, local and
public-network results must be reported separately. Test success never approves a
visual baseline or independently certifies the transport/identity protocol.
