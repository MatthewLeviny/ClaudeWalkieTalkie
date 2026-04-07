import SwiftUI
import AppKit

/// The content view shown in the menu bar dropdown.
public struct MenuBarView: View {
    @Environment(WebSocketServer.self) var server
    @Environment(SessionDiscovery.self) var discovery

    public init() {}

    // MARK: - Dashboard Window Constants

    private static let dashboardWindowWidth: CGFloat = 800
    private static let dashboardWindowHeight: CGFloat = 500
    private static let dashboardMinWidth: CGFloat = 600
    private static let dashboardMinHeight: CGFloat = 400

    /// Retained reference so ARC doesn't deallocate the window.
    @State private var dashboardWindow: NSWindow?

    public var body: some View {
        Group {
            if server.isRunning {
                if let ip = WebSocketServer.localIPAddress(), let port = server.port {
                    Text("\(ip):\(port)")
                } else if let port = server.port {
                    Text("Port \(port)")
                }

                Text("\(server.connectedClients) client(s) connected")

                if let code = server.pairingCode {
                    Text("Pair: \(code)")
                }
            } else {
                Text("Server Stopped")
            }

            Text("\(discovery.sessions.count) session(s)")

            Divider()

            Button(server.isRunning ? "Stop Server" : "Start Server") {
                if server.isRunning {
                    server.stop()
                } else {
                    server.start()
                }
            }

            Button("Open Dashboard") {
                showDashboard()
            }

            Divider()

            Button("Quit ClaudeMulti") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func showDashboard() {
        // If window already exists, just show it
        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // Create a new window with the dashboard view
        let view = DashboardWindow()
            .environment(server)
            .environment(discovery)

        let hosting = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.dashboardWindowWidth, height: Self.dashboardWindowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeMulti Dashboard"
        window.contentView = hosting
        window.minSize = NSSize(width: Self.dashboardMinWidth, height: Self.dashboardMinHeight)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)

        dashboardWindow = window
    }
}
