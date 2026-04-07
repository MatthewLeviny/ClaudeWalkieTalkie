import Foundation

/// Represents a discovered terminal session window on the Mac.
public struct TerminalSession: Codable, Identifiable, Equatable {
    /// Unique identifier for this session (UUID string).
    public let id: String
    /// The macOS window ID (CGWindowID).
    public let windowId: Int
    /// The window title (e.g. iTerm2 tab name).
    public var title: String
    /// The window's bounds on screen.
    public var bounds: SessionBounds
    /// Whether this session is currently selected for text injection.
    public var isSelected: Bool

    /// Screen-space bounds for a window or screen region.
    public struct SessionBounds: Codable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public init(
        id: String = UUID().uuidString,
        windowId: Int,
        title: String,
        bounds: SessionBounds,
        isSelected: Bool = false
    ) {
        self.id = id
        self.windowId = windowId
        self.title = title
        self.bounds = bounds
        self.isSelected = isSelected
    }
}
