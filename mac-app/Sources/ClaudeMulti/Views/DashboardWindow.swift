import SwiftUI
import CoreGraphics

/// The main dashboard window showing session management, layout controls,
/// connection info, and the window map preview.
@MainActor
public struct DashboardWindow: View {
    @Environment(WebSocketServer.self) var server
    @Environment(SessionDiscovery.self) var discovery

    public init() {}
    @State private var selectedLayout: LayoutPreset = .grid
    @State private var hasAccessibilityPermission: Bool = true
    @State private var hasScreenRecordingPermission: Bool = true
    @State private var showScreenRecordingWarning: Bool = false
    @State private var showOnboarding: Bool = false

    /// Delay before checking if Screen Recording permission has taken effect.
    /// After the initial scan completes, the system may still be processing
    /// the permission grant, so we wait before warning about missing sessions.
    private static let screenRecordingCheckDelay: TimeInterval = 3.0

    private let tiler = WindowTiler()

    public var body: some View {
        HSplitView {
            // Left panel
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showOnboarding {
                        onboardingCard
                    }

                    permissionBanners

                    connectionInfoSection
                    Divider()
                    layoutSection
                    Divider()
                    sessionListSection
                }
                .padding()
            }
            .frame(minWidth: 280, idealWidth: 320)

            // Right panel: window map preview
            VStack {
                Text("Window Map")
                    .font(.headline)
                    .padding(.top)

                WindowMapPreview(
                    sessions: discovery.sessions,
                    screenBounds: currentScreenBounds,
                    selectedSessionId: discovery.selectedSessionId
                )
                .padding()
            }
            .frame(minWidth: 300, idealWidth: 400)
        }
        .onAppear {
            checkPermissions()
            evaluateOnboarding()
            // Only start discovery if permission is already granted
            if hasScreenRecordingPermission {
                discovery.startDiscovery()
            }
        }
        .onChange(of: discovery.hasCompletedInitialScan) { _, completed in
            if completed {
                // After initial scan, check if we found any sessions
                // Give a brief delay for Screen Recording to kick in
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.screenRecordingCheckDelay) {
                    if discovery.sessions.isEmpty && discovery.hasCompletedInitialScan {
                        showScreenRecordingWarning = true
                    }
                }
            }
        }
        .onChange(of: discovery.sessions) { _, sessions in
            // If sessions appear, dismiss the Screen Recording warning
            if !sessions.isEmpty {
                showScreenRecordingWarning = false
            }
        }
    }

    /// The current main screen bounds, used for tiling calculations.
    private var currentScreenBounds: TerminalSession.SessionBounds {
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            return TerminalSession.SessionBounds(
                x: Double(frame.origin.x),
                y: Double(frame.origin.y),
                width: Double(frame.size.width),
                height: Double(frame.size.height)
            )
        }
        return TerminalSession.SessionBounds(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func checkPermissions() {
        hasAccessibilityPermission = WindowTiler.checkAccessibilityPermission()
        checkScreenRecordingPermission()
    }

    private func checkScreenRecordingPermission() {
        // Use preflight check — does NOT trigger a permission prompt
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    /// Show onboarding if any required permission is missing.
    private func evaluateOnboarding() {
        // Show onboarding on first launch or when permissions are missing
        let hasLaunched = UserDefaults.standard.bool(forKey: "ClaudeMulti.hasLaunchedBefore")
        if !hasLaunched {
            showOnboarding = true
            UserDefaults.standard.set(true, forKey: "ClaudeMulti.hasLaunchedBefore")
        } else if !hasAccessibilityPermission || !hasScreenRecordingPermission {
            showOnboarding = true
        }
    }

    // MARK: - Onboarding Card

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Setup Permissions")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    withAnimation { showOnboarding = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("ClaudeMulti needs a few permissions to manage your terminal windows.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Step 1: Accessibility
            onboardingStep(
                number: 1,
                title: "Accessibility",
                description: "Required to move and resize terminal windows.",
                isGranted: hasAccessibilityPermission,
                action: {
                    WindowTiler.requestAccessibilityPermission()
                },
                actionLabel: "Open Settings"
            )

            // Step 2: Screen Recording
            onboardingStep(
                number: 2,
                title: "Screen Recording",
                description: "Required to discover terminal windows on screen.",
                isGranted: hasScreenRecordingPermission,
                action: {
                    WindowTiler.requestScreenRecordingPermission()
                },
                actionLabel: "Open Settings"
            )

            // Step 3: Automation (iTerm2)
            onboardingStep(
                number: 3,
                title: "Automation (iTerm2)",
                description: "Will be requested on first text injection. No action needed now.",
                isGranted: nil,
                action: nil,
                actionLabel: nil
            )

            HStack {
                Spacer()
                Button("Refresh Status") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if hasAccessibilityPermission && hasScreenRecordingPermission {
                    Button("Done") {
                        withAnimation { showOnboarding = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// A single step in the onboarding flow.
    /// `isGranted`: true = green check, false = yellow warning, nil = info (no check possible).
    @ViewBuilder
    private func onboardingStep(
        number: Int,
        title: String,
        description: String,
        isGranted: Bool?,
        action: (() -> Void)?,
        actionLabel: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon
            Group {
                if let granted = isGranted {
                    if granted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                } else {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .font(.title3)
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(number): \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let granted = isGranted, !granted, let action = action, let label = actionLabel {
                    Button(label, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Permission Banners

    @ViewBuilder
    private var permissionBanners: some View {
        if !hasAccessibilityPermission && !showOnboarding {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Required")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("ClaudeMulti needs Accessibility access to move and resize terminal windows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    WindowTiler.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Refresh") {
                    checkPermissions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.orange.opacity(0.3)),
                alignment: .bottom
            )
        }

        if showScreenRecordingWarning && !showOnboarding {
            HStack {
                Image(systemName: "video.slash.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording Permission Required")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("ClaudeMulti needs Screen Recording access to discover terminal windows. Grant permission and restart the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    WindowTiler.requestScreenRecordingPermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.red.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.red.opacity(0.3)),
                alignment: .bottom
            )
        }
    }

    // MARK: - Sections

    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection")
                .font(.headline)

            HStack {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(server.isRunning ? "Server Running" : "Server Stopped")
            }

            if server.isRunning {
                // Prominent local IP display for manual Android connection
                if let ip = WebSocketServer.localIPAddress(), let port = server.port {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect from Android")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(ip):\(port)")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                } else if let port = server.port {
                    HStack {
                        Image(systemName: "network")
                        Text("localhost:\(port)")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                HStack {
                    Image(systemName: "iphone")
                    Text("\(server.connectedClients) client(s)")
                }
            }

            if let code = server.pairingCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pairing Code")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(code)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }

            HStack {
                Button(server.isRunning ? "Stop" : "Start") {
                    if server.isRunning {
                        server.stop()
                    } else {
                        server.start()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout")
                .font(.headline)

            Picker("Preset", selection: $selectedLayout) {
                ForEach(LayoutPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Button("Apply Layout") {
                let updated = tiler.applyLayout(
                    selectedLayout,
                    to: discovery.sessions,
                    screenBounds: currentScreenBounds,
                    discovery: discovery
                )
                discovery.sessions = updated
            }
            .buttonStyle(.bordered)
            .disabled(discovery.sessions.isEmpty)
        }
    }

    private var sessionListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions (\(discovery.sessions.count))")
                .font(.headline)

            if discovery.sessions.isEmpty {
                Text("No terminal sessions found.")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List(discovery.sessions) { session in
                    HStack {
                        Image(systemName: session.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(session.isSelected ? .accentColor : .secondary)
                        VStack(alignment: .leading) {
                            Text(session.title)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            Text("Window \(session.windowId) | \(Int(session.bounds.width))x\(Int(session.bounds.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        discovery.selectSession(session.id)
                    }
                }
                .listStyle(.inset)
            }

            Button("Refresh") {
                checkPermissions()
                // Force discovery — bypass preflight check
                discovery.hasScreenRecordingPermission = true
                discovery.startDiscovery()
            }
            .buttonStyle(.bordered)
        }
    }
}
