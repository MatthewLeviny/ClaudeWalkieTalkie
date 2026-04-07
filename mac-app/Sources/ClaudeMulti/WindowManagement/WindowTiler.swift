import Foundation
import ApplicationServices
import AppKit
import os

/// Predefined layout presets for arranging terminal windows on screen.
public enum LayoutPreset: String, CaseIterable, Identifiable {
    /// Equal-sized grid (2x2, 2x3, etc. depending on session count).
    case grid
    /// One large main window on the left, smaller sidebar windows stacked on the right.
    case mainSidebar
    /// Equal-width columns side by side.
    case columns
    /// Equal-height rows stacked vertically.
    case rows

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .grid:        return "Grid"
        case .mainSidebar: return "Main + Sidebar"
        case .columns:     return "Columns"
        case .rows:        return "Rows"
        }
    }
}

/// Calculates and applies window layouts to terminal sessions using Accessibility APIs.
public final class WindowTiler {

    private static let logger = Logger(subsystem: "com.claudemulti.mac", category: "WindowTiler")

    public init() {}

    /// Fraction of screen width allocated to the main window in mainSidebar layout.
    private static let mainSplitRatio: Double = 0.6
    /// Fraction of screen width allocated to the sidebar in mainSidebar layout.
    private static let sidebarSplitRatio: Double = 0.4

    /// Calculate and apply a layout to the given sessions within the screen bounds.
    ///
    /// Uses AXUIElement APIs to actually reposition windows on screen.
    ///
    /// - Parameters:
    ///   - preset: The layout arrangement to apply.
    ///   - sessions: The terminal sessions to reposition.
    ///   - screenBounds: The available screen area for tiling.
    ///   - discovery: The SessionDiscovery instance used to find AXUIElement windows.
    /// - Returns: Updated sessions with new bounds reflecting the layout.
    public func applyLayout(
        _ preset: LayoutPreset,
        to sessions: [TerminalSession],
        screenBounds: TerminalSession.SessionBounds,
        discovery: SessionDiscovery? = nil
    ) -> [TerminalSession] {
        guard !sessions.isEmpty else { return sessions }

        let calculatedBounds = calculateBounds(
            preset: preset,
            count: sessions.count,
            screen: screenBounds
        )

        var updated = sessions
        for i in updated.indices {
            if i < calculatedBounds.count {
                updated[i].bounds = calculatedBounds[i]

                // Actually move the window if we have a discovery reference
                if let discovery = discovery {
                    let session = updated[i]
                    let bounds = calculatedBounds[i]

                    if let axWindow = discovery.findAXWindow(for: sessions[i]) {
                        setWindowPosition(axWindow, x: bounds.x, y: bounds.y)
                        setWindowSize(axWindow, width: bounds.width, height: bounds.height)
                        Self.logger.info("Moved window '\(session.title)' to (\(Int(bounds.x)), \(Int(bounds.y))) size \(Int(bounds.width))x\(Int(bounds.height))")
                    } else {
                        Self.logger.warning("Could not find AX window for '\(session.title)' — skipping")
                    }
                }
            }
        }

        Self.logger.info("Applied \(preset.rawValue) layout to \(sessions.count) sessions")
        return updated
    }

    // MARK: - AXUIElement Window Manipulation

    /// Set the position of an AXUIElement window.
    private func setWindowPosition(_ window: AXUIElement, x: Double, y: Double) {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else {
            Self.logger.error("Failed to create AXValue for position")
            return
        }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success {
            Self.logger.error("Failed to set window position: AXError \(result.rawValue)")
        }
    }

    /// Set the size of an AXUIElement window.
    private func setWindowSize(_ window: AXUIElement, width: Double, height: Double) {
        var size = CGSize(width: width, height: height)
        guard let value = AXValueCreate(.cgSize, &size) else {
            Self.logger.error("Failed to create AXValue for size")
            return
        }
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        if result != .success {
            Self.logger.error("Failed to set window size: AXError \(result.rawValue)")
        }
    }

    // MARK: - Permission Checks

    /// Check whether the app has Accessibility permission (required for window manipulation).
    public static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Open System Settings to the Accessibility pane so the user can grant permission.
    public static func requestAccessibilityPermission() {
        // On macOS 13+, open System Settings > Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings to the Screen Recording pane so the user can grant permission.
    public static func requestScreenRecordingPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Layout Calculation

    private func calculateBounds(
        preset: LayoutPreset,
        count: Int,
        screen: TerminalSession.SessionBounds
    ) -> [TerminalSession.SessionBounds] {
        switch preset {
        case .grid:
            return calculateGrid(count: count, screen: screen)
        case .mainSidebar:
            return calculateMainSidebar(count: count, screen: screen)
        case .columns:
            return calculateColumns(count: count, screen: screen)
        case .rows:
            return calculateRows(count: count, screen: screen)
        }
    }

    private func calculateGrid(count: Int, screen: TerminalSession.SessionBounds) -> [TerminalSession.SessionBounds] {
        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let cellWidth = screen.width / Double(cols)
        let cellHeight = screen.height / Double(rows)

        var bounds: [TerminalSession.SessionBounds] = []
        for i in 0..<count {
            let col = i % cols
            let row = i / cols
            bounds.append(.init(
                x: screen.x + Double(col) * cellWidth,
                y: screen.y + Double(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ))
        }
        return bounds
    }

    private func calculateMainSidebar(count: Int, screen: TerminalSession.SessionBounds) -> [TerminalSession.SessionBounds] {
        guard count > 1 else {
            return [screen]
        }
        let mainWidth = screen.width * Self.mainSplitRatio
        let sideWidth = screen.width * Self.sidebarSplitRatio
        let sideHeight = screen.height / Double(count - 1)

        var bounds: [TerminalSession.SessionBounds] = []
        // Main window
        bounds.append(.init(x: screen.x, y: screen.y, width: mainWidth, height: screen.height))
        // Sidebar windows
        for i in 1..<count {
            bounds.append(.init(
                x: screen.x + mainWidth,
                y: screen.y + Double(i - 1) * sideHeight,
                width: sideWidth,
                height: sideHeight
            ))
        }
        return bounds
    }

    private func calculateColumns(count: Int, screen: TerminalSession.SessionBounds) -> [TerminalSession.SessionBounds] {
        let colWidth = screen.width / Double(count)
        return (0..<count).map { i in
            .init(
                x: screen.x + Double(i) * colWidth,
                y: screen.y,
                width: colWidth,
                height: screen.height
            )
        }
    }

    private func calculateRows(count: Int, screen: TerminalSession.SessionBounds) -> [TerminalSession.SessionBounds] {
        let rowHeight = screen.height / Double(count)
        return (0..<count).map { i in
            .init(
                x: screen.x,
                y: screen.y + Double(i) * rowHeight,
                width: screen.width,
                height: rowHeight
            )
        }
    }
}
