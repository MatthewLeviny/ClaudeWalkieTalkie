import Foundation
import Network
import Security
import os

#if canImport(Darwin)
import Darwin
#endif

/// WebSocket server that listens for connections from iOS/iPadOS clients.
///
/// Uses Network.framework's NWListener with NWProtocolWebSocket for native
/// WebSocket support without any third-party dependencies. Bonjour advertisement
/// is handled directly by the NWListener.Service configuration.
@MainActor
@Observable
public final class WebSocketServer {
    /// Default TCP port for the WebSocket server.
    public init() {}

    nonisolated public static let defaultPort: UInt16 = 8765

    public var isRunning = false
    public var connectedClients = 0
    public var pairingCode: String?

    private nonisolated static let logger = Logger(subsystem: "com.claudemulti.mac", category: "WebSocketServer")

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    /// Maps NWConnection hashValue to the deviceId that paired on that connection.
    private var connectionDeviceIds: [Int: String] = [:]

    /// Set of device IDs that have been paired (persisted in UserDefaults).
    private var pairedDeviceIds: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "ClaudeMulti.pairedDeviceIds") ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "ClaudeMulti.pairedDeviceIds")
        }
    }

    /// Callback invoked when a message is received from a paired client.
    public var onMessageReceived: ((WSMessage, NWConnection) -> Void)?

    /// The port the server is currently listening on, if running.
    public var port: UInt16? {
        listener?.port?.rawValue
    }

    // MARK: - Local IP Address

    /// Returns the device's local network IP address (en0 / WiFi interface).
    ///
    /// Uses `getifaddrs` to enumerate network interfaces and returns the first
    /// IPv4 address found on the `en0` interface. Returns nil if unavailable.
    public static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var address: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        &addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0,
                        NI_NUMERICHOST
                    ) == 0 {
                        address = String(cString: hostname)
                    }
                }
            }
            cursor = interface.ifa_next
        }
        return address
    }

    // MARK: - Lifecycle

    /// Start listening for WebSocket connections on the given port.
    ///
    /// - Parameter port: The TCP port to bind. Defaults to 8765.
    public func start(port: UInt16 = WebSocketServer.defaultPort) {
        // Stop any existing listener first
        stop()

        // Generate a cryptographically secure 6-digit pairing code
        pairingCode = generatePairingCode()

        // Configure WebSocket protocol
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                Self.logger.error("Invalid port: \(port)")
                return
            }
            let newListener = try NWListener(using: parameters, on: nwPort)

            // Bonjour advertisement
            newListener.service = NWListener.Service(
                name: "ClaudeMulti",
                type: BonjourAdvertiser.serviceType
            )

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.handleListenerState(state)
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.handleNewConnection(connection)
                }
            }

            newListener.start(queue: .main)
            listener = newListener
            Self.logger.info("Starting on port \(port)")
        } catch {
            Self.logger.error("Failed to create listener: \(error)")
            isRunning = false
        }
    }

    /// Stop the server and disconnect all clients.
    ///
    /// Sends a WebSocket close frame to each connection before cancelling,
    /// allowing clients to handle the disconnect gracefully.
    public func stop() {
        // Send close frames to all connections before cancelling
        for connection in connections {
            let closeMetadata = NWProtocolWebSocket.Metadata(opcode: .close)
            closeMetadata.closeCode = .protocolCode(.normalClosure)
            let context = NWConnection.ContentContext(
                identifier: "wsClose",
                metadata: [closeMetadata]
            )
            connection.send(
                content: nil,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { _ in
                    connection.cancel()
                }
            )
        }
        connections.removeAll()
        connectionDeviceIds.removeAll()
        listener?.cancel()
        listener = nil

        isRunning = false
        connectedClients = 0
        pairingCode = nil
        Self.logger.info("Stopped")
    }

    /// Broadcast a message to all connected clients.
    ///
    /// - Parameter message: The WSMessage to encode and send.
    public func broadcast(_ message: WSMessage) {
        guard let data = try? JSONEncoder().encode(message) else {
            Self.logger.error("Failed to encode broadcast message")
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "wsMessage",
            metadata: [metadata]
        )

        for connection in connections {
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error = error {
                        Self.logger.error("Send error: \(error)")
                    }
                }
            )
        }
        Self.logger.debug("Broadcast \(data.count) bytes to \(self.connections.count) client(s)")
    }

    /// Send a message to a specific connection.
    ///
    /// - Parameters:
    ///   - message: The WSMessage to encode and send.
    ///   - connection: The target connection.
    public func send(_ message: WSMessage, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else {
            Self.logger.error("Failed to encode message")
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "wsMessage",
            metadata: [metadata]
        )

        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error = error {
                    Self.logger.error("Send error: \(error)")
                }
            }
        )
    }

    // MARK: - Pairing Code Generation

    /// Generate a cryptographically secure 6-digit pairing code using SecRandomCopyBytes.
    private func generatePairingCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let number = (UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])) % 1_000_000
        return String(format: "%06d", number)
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            Self.logger.info("Ready on port \(self.listener?.port?.rawValue ?? 0)")
        case .failed(let error):
            isRunning = false
            Self.logger.error("Listener failed: \(error)")
            // Attempt to restart after a short delay
            listener?.cancel()
            listener = nil
        case .cancelled:
            isRunning = false
            Self.logger.info("Listener cancelled")
        default:
            break
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectedClients = connections.count

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleConnectionState(state, connection: connection)
            }
        }

        connection.start(queue: .main)
        receiveMessage(on: connection)

        Self.logger.info("New connection (\(self.connections.count) total)")
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            Self.logger.debug("Connection ready")
        case .failed(let error):
            Self.logger.error("Connection failed: \(error)")
            removeConnection(connection)
        case .cancelled:
            Self.logger.info("Connection cancelled")
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connectionDeviceIds.removeValue(forKey: ObjectIdentifier(connection).hashValue)
        connectedClients = connections.count
    }

    // MARK: - Message Receive Loop

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self else { return }
            DispatchQueue.main.async {

                if let error = error {
                    Self.logger.error("Receive error: \(error)")
                    self.removeConnection(connection)
                    return
                }

                // Check if this is a WebSocket text frame
                if let context = context,
                   let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                    switch metadata.opcode {
                    case .text:
                        if let data = content {
                            self.handleTextMessage(data, from: connection)
                        }
                    case .close:
                        Self.logger.info("Received close frame")
                        self.removeConnection(connection)
                        connection.cancel()
                        return
                    default:
                        break
                    }
                }

                // Continue receiving if connection is still tracked
                if self.connections.contains(where: { $0 === connection }) {
                    self.receiveMessage(on: connection)
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleTextMessage(_ data: Data, from connection: NWConnection) {
        let decoder = JSONDecoder()
        guard let message = try? decoder.decode(WSMessage.self, from: data) else {
            Self.logger.warning("Failed to decode message: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            return
        }

        // Pairing messages are always allowed
        if case .pair(let pairMsg) = message {
            handlePairMessage(pairMsg, from: connection)
            return
        }

        // All other messages require the connection to be paired
        let connectionKey = ObjectIdentifier(connection).hashValue
        guard let deviceId = connectionDeviceIds[connectionKey],
              pairedDeviceIds.contains(deviceId) else {
            let errorMsg = WSMessage.error(ErrorMessage(message: "not paired"))
            send(errorMsg, to: connection)
            Self.logger.warning("Rejected message from unpaired connection")
            return
        }

        // Dispatch to the app-level handler
        onMessageReceived?(message, connection)
    }

    private func handlePairMessage(_ pairMsg: PairMessage, from connection: NWConnection) {
        guard let currentCode = pairingCode else {
            let result = WSMessage.pairResult(PairResultMessage(
                success: false,
                message: "Server has no active pairing code"
            ))
            send(result, to: connection)
            return
        }

        if pairMsg.code == currentCode {
            // Pairing successful
            var deviceIds = pairedDeviceIds
            deviceIds.insert(pairMsg.deviceId)
            pairedDeviceIds = deviceIds

            let connectionKey = ObjectIdentifier(connection).hashValue
            connectionDeviceIds[connectionKey] = pairMsg.deviceId

            let result = WSMessage.pairResult(PairResultMessage(
                success: true,
                message: "Paired successfully"
            ))
            send(result, to: connection)
            Self.logger.info("Device \(pairMsg.deviceId) paired successfully")
        } else {
            // Invalid code
            let result = WSMessage.pairResult(PairResultMessage(
                success: false,
                message: "Invalid pairing code"
            ))
            send(result, to: connection)
            Self.logger.warning("Pairing failed for device \(pairMsg.deviceId) — wrong code")
        }
    }
}
