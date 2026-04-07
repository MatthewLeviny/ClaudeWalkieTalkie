import Foundation
import ScreenCaptureKit
import AppKit
import ApplicationServices
import os

/// Discovers and tracks open terminal windows (iTerm2, Terminal.app, etc.)
/// using ScreenCaptureKit for window enumeration and Accessibility APIs for
/// detailed window properties.
@MainActor
@Observable
public final class SessionDiscovery {
    public init() {}

    public var sessions: [TerminalSession] = []

    /// The currently selected session ID, if any.
    public var selectedSessionId: String?

    /// Set to true once initial discovery has completed at least once.
    public var hasCompletedInitialScan: Bool = false

    /// How often to poll for window changes (in seconds).
    public var pollInterval: TimeInterval = 2.0

    private var pollTimer: Timer?

    /// Whether Screen Recording permission has been confirmed.
    public var hasScreenRecordingPermission: Bool = false

    /// Callback invoked when sessions change (used to notify server of state updates).
    public var onSessionsChanged: (() -> Void)?

    /// Callback invoked when the selected session changes.
    public var onSelectedSessionChanged: ((String) -> Void)?

    private nonisolated static let logger = Logger(subsystem: "com.claudemulti.mac", category: "SessionDiscovery")

    /// Bundle identifier for iTerm2.
    private nonisolated static let iterm2BundleID = "com.googlecode.iterm2"

    /// Tolerance (in points) for matching AX window position/size to SCWindow data.
    private nonisolated static let positionTolerance: Double = 5.0

    // MARK: - Discovery

    /// Start discovering terminal sessions.
    ///
    /// Performs an initial scan, then polls at `pollInterval`.
    public func startDiscovery() {
        // Cancel any existing timer
        pollTimer?.invalidate()
        pollTimer = nil

        // Perform initial scan
        Task {
            await performScan()
        }

        // Set up repeating timer for polling
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performScan()
            }
        }
    }

    /// Stop polling for session changes.
    public func stopDiscovery() {
        pollTimer?.invalidate()
        pollTimer = nil
        Self.logger.info("Stopped discovery")
    }

    /// Select a session by ID.
    public func selectSession(_ sessionId: String) {
        selectedSessionId = sessionId
        for i in sessions.indices {
            sessions[i].isSelected = (sessions[i].id == sessionId)
        }
        onSelectedSessionChanged?(sessionId)
    }

    /// Cycle selection to the next or previous session.
    public func cycleSelection(direction: CycleDirection) {
        guard !sessions.isEmpty else { return }
        let currentIndex = sessions.firstIndex(where: { $0.id == selectedSessionId }) ?? 0
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (currentIndex + 1) % sessions.count
        case .prev:
            nextIndex = (currentIndex - 1 + sessions.count) % sessions.count
        }
        selectSession(sessions[nextIndex].id)
    }

    /// Check Screen Recording permission without triggering a prompt.
    public func checkScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    // MARK: - SCShareableContent Scanning

    /// Perform a single scan for terminal windows using ScreenCaptureKit.
    private func performScan() async {
        // Check permission before calling SCShareableContent to avoid repeated prompts
        if !hasScreenRecordingPermission {
            hasScreenRecordingPermission = checkScreenRecordingPermission()
            if !hasScreenRecordingPermission {
                if !hasCompletedInitialScan {
                    hasCompletedInitialScan = true
                }
                return
            }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Check if content is empty — may indicate missing Screen Recording permission
            if content.windows.isEmpty && content.applications.isEmpty {
                Self.logger.warning("SCShareableContent returned empty results. Screen Recording permission may not be granted.")
            }

            // Filter for iTerm2 windows — match by bundle ID or app name
            let iterm2Windows = content.windows.filter { window in
                guard let app = window.owningApplication else { return false }
                if app.bundleIdentifier == Self.iterm2BundleID { return true }
                if app.applicationName.lowercased().contains("iterm") { return true }
                return false
            }

            Self.logger.debug("Found \(content.windows.count) total windows, \(iterm2Windows.count) iTerm2 windows")
            #if DEBUG
            if iterm2Windows.isEmpty {
                // Debug: list all apps with names for troubleshooting
                let appInfo = content.applications.map { "\($0.applicationName)=\($0.bundleIdentifier)" }
                Self.logger.debug("All apps: \(appInfo)")
            }
            #endif

            // Remember currently selected IDs for preserving selection state
            let previouslySelectedId = selectedSessionId
            let previousSelectionSet = Set(sessions.filter(\.isSelected).map(\.id))

            // Map SCWindows to TerminalSession structs
            let newSessions: [TerminalSession] = iterm2Windows.map { window in
                let windowID = Int(window.windowID)
                let stableId = "iterm2-\(windowID)"
                let frame = window.frame
                let title = window.title ?? "iTerm2 Window \(windowID)"
                let wasSelected = previousSelectionSet.contains(stableId)

                return TerminalSession(
                    id: stableId,
                    windowId: windowID,
                    title: title,
                    bounds: .init(
                        x: Double(frame.origin.x),
                        y: Double(frame.origin.y),
                        width: Double(frame.size.width),
                        height: Double(frame.size.height)
                    ),
                    isSelected: wasSelected
                )
            }

            // Update state
            let previousSessions = sessions
            sessions = newSessions

            // Preserve selection: if the previously selected session still exists, keep it
            if let prevId = previouslySelectedId, newSessions.contains(where: { $0.id == prevId }) {
                selectSession(prevId)
            } else if selectedSessionId == nil || !newSessions.contains(where: { $0.id == selectedSessionId }) {
                // If nothing selected or selected session disappeared, select first
                if let first = newSessions.first {
                    selectSession(first.id)
                } else {
                    selectedSessionId = nil
                }
            }

            if !hasCompletedInitialScan {
                hasCompletedInitialScan = true
            }

            // Notify listener if sessions actually changed
            if previousSessions != newSessions {
                onSessionsChanged?()
            }

        } catch {
            let desc = error.localizedDescription
            Self.logger.error("Error scanning windows: \(desc)")

            // If permission was declined, stop polling to avoid spam
            if desc.contains("TCC") || desc.contains("declined") {
                hasScreenRecordingPermission = false
                stopDiscovery()
                Self.logger.error("Screen Recording permission denied — polling stopped. Grant permission and click Refresh.")
            }

            if !hasCompletedInitialScan {
                hasCompletedInitialScan = true
            }
        }
    }

    // MARK: - AXUIElement Window Matching

    /// Find the AXUIElement window corresponding to a given TerminalSession.
    ///
    /// This matches by comparing window title and position/size against the
    /// TerminalSession data obtained from ScreenCaptureKit.
    ///
    /// - Parameter session: The terminal session to find an AXUIElement for.
    /// - Returns: The matching AXUIElement, or nil if not found.
    nonisolated public func findAXWindow(for session: TerminalSession) -> AXUIElement? {
        // Find iTerm2's PID from running applications
        guard let iterm2App = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.iterm2BundleID
        ).first else {
            Self.logger.warning("iTerm2 is not running")
            return nil
        }

        let pid = iterm2App.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get the windows attribute
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            Self.logger.error("Failed to get AX windows: \(result.rawValue)")
            return nil
        }

        // Try to match by title first
        for window in windows {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if titleResult == .success, let title = titleRef as? String {
                if title == session.title {
                    return window
                }
            }
        }

        // Fallback: match by position and size
        for window in windows {
            var positionRef: CFTypeRef?
            var sizeRef: CFTypeRef?

            let posResult = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
            let sizeResult = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

            if posResult == .success, sizeResult == .success {
                var point = CGPoint.zero
                var size = CGSize.zero

                if AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
                   AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
                    // Allow small tolerance for position/size comparison
                    if abs(Double(point.x) - session.bounds.x) < Self.positionTolerance &&
                       abs(Double(point.y) - session.bounds.y) < Self.positionTolerance &&
                       abs(Double(size.width) - session.bounds.width) < Self.positionTolerance &&
                       abs(Double(size.height) - session.bounds.height) < Self.positionTolerance {
                        return window
                    }
                }
            }
        }

        Self.logger.debug("Could not find AX window for session: \(session.title)")
        return nil
    }
}
