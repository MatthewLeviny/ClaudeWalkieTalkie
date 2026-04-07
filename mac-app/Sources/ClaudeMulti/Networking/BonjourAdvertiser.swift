import Foundation
import Network
import os

/// Constants and utilities for Bonjour / mDNS service advertisement.
///
/// Bonjour advertisement is handled directly by NWListener.Service inside
/// WebSocketServer. This class provides the shared service type constant
/// and can be extended if manual Bonjour control is needed in the future
/// (e.g. updating TXT records with pairing metadata).
@Observable
public final class BonjourAdvertiser {
    public var isAdvertising = false

    private static let logger = Logger(subsystem: "com.claudemulti.mac", category: "BonjourAdvertiser")

    /// The Bonjour service type. Clients search for this to find the Mac.
    public static let serviceType = "_claudemulti._tcp"

    /// Reference to the WebSocket server whose listener handles advertisement.
    private weak var server: WebSocketServer?

    /// Initialize with a reference to the WebSocket server.
    ///
    /// The server's NWListener.Service handles actual Bonjour advertisement.
    /// This class tracks the advertising state by observing the server.
    public init(server: WebSocketServer? = nil) {
        self.server = server
    }

    /// Update advertising state based on the server's running state.
    ///
    /// Call this when the server starts or stops to keep state in sync.
    @MainActor public func syncWithServer(_ server: WebSocketServer) {
        self.server = server
        isAdvertising = server.isRunning
    }

    /// Convenience: the Bonjour service name used for advertisement.
    public static let serviceName = "ClaudeMulti"
}
