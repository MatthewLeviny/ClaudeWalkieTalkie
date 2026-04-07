import SwiftUI
import Network
import AppKit
import ClaudeMultiLib

@main
struct ClaudeMultiApp: App {
    @State private var server = WebSocketServer()
    @State private var discovery = SessionDiscovery()

    /// Maximum text length accepted in sendText messages.
    private static let maxSendTextLength = 10_000

    private let textInjection = TextInjection()

    @State private var hasWiredUp = false

    var body: some Scene {
        MenuBarExtra("ClaudeMulti", systemImage: "terminal.fill") {
            MenuBarView()
                .environment(server)
                .environment(discovery)
                .onAppear { wireUpOnce() }
        }
    }

    private func wireUpOnce() {
        guard !hasWiredUp else { return }
        hasWiredUp = true

        // Start server
        server.start()

        // Only start discovery if Screen Recording is already granted
        if discovery.checkScreenRecordingPermission() {
            discovery.startDiscovery()
        }

        // Handle incoming WebSocket messages
        server.onMessageReceived = { [self] message, connection in
            handleMessage(message, from: connection)
        }

        // Broadcast state to clients whenever sessions change
        discovery.onSessionsChanged = { [self] in
            broadcastStateSync()
        }

        // Also broadcast when selected session changes
        discovery.onSelectedSessionChanged = { [self] selectedId in
            let msg = WSMessage.selectionChanged(
                SelectionChangedMessage(selectedSessionId: selectedId)
            )
            server.broadcast(msg)
        }

        // Graceful shutdown: stop server and discovery when the app terminates
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                server.stop()
                discovery.stopDiscovery()
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WSMessage, from connection: NWConnection) {
        switch message {
        case .cycleSelection(let msg):
            discovery.cycleSelection(direction: msg.direction)

        case .sendText(let msg):
            // Validate text length before processing
            guard msg.text.count <= Self.maxSendTextLength else {
                #if DEBUG
                print("[ClaudeMultiApp] Rejected sendText: too long (\(msg.text.count) chars)")
                #endif
                break
            }

            // Strip control characters (except newline if pressEnter is true, and tab)
            let validatedText = String(msg.text.filter { char in
                guard let scalar = char.unicodeScalars.first else { return false }
                if scalar.value < 0x20 {
                    // Allow tab always
                    if scalar.value == 0x09 { return true }
                    // Allow newline only if pressEnter is true
                    if scalar.value == 0x0A && msg.pressEnter { return true }
                    return false
                }
                return true
            })

            let targetSessionId = msg.sessionId ?? discovery.selectedSessionId
            if let sessionId = targetSessionId {
                if let session = discovery.sessions.first(where: { $0.id == sessionId }) {
                    textInjection.sendText(validatedText, toWindowId: session.windowId, pressEnter: msg.pressEnter)
                } else {
                    textInjection.sendText(validatedText, toSession: sessionId, pressEnter: msg.pressEnter)
                }
            } else {
                textInjection.sendText(validatedText, toSession: "current", pressEnter: msg.pressEnter)
            }

        case .requestSync:
            broadcastStateSync()

        case .selectionChanged(let msg):
            discovery.selectSession(msg.selectedSessionId)

        default:
            break
        }
    }

    private func broadcastStateSync() {
        let screenBounds: TerminalSession.SessionBounds
        if !discovery.sessions.isEmpty {
            let minX = discovery.sessions.map(\.bounds.x).min() ?? 0
            let minY = discovery.sessions.map(\.bounds.y).min() ?? 0
            let maxX = discovery.sessions.map { $0.bounds.x + $0.bounds.width }.max() ?? 1920
            let maxY = discovery.sessions.map { $0.bounds.y + $0.bounds.height }.max() ?? 1080
            screenBounds = TerminalSession.SessionBounds(
                x: minX, y: minY, width: maxX - minX, height: maxY - minY
            )
        } else {
            screenBounds = TerminalSession.SessionBounds(x: 0, y: 0, width: 1920, height: 1080)
        }

        let syncMsg = WSMessage.stateSync(
            StateSyncMessage(sessions: discovery.sessions, screenBounds: screenBounds)
        )
        server.broadcast(syncMsg)
    }
}
