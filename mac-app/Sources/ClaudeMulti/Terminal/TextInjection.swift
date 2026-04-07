import Foundation
import os

/// Injects text into specific iTerm2 terminal sessions using AppleScript.
///
/// This communicates with iTerm2's scripting interface to write text into
/// targeted sessions without relying on clipboard or simulated keystrokes.
public final class TextInjection {

    public init() {}

    private static let logger = Logger(subsystem: "com.claudemulti.mac", category: "TextInjection")

    /// Maximum allowed text length to prevent abuse.
    private static let maxTextLength = 10_000

    /// Minimum interval between injections (rate limiting).
    private static let minInjectionInterval: TimeInterval = 0.1  // 10 per second max

    /// Timestamp of the last injection for rate limiting.
    private var lastInjectionTime: Date = .distantPast

    // MARK: - Sanitization

    /// Sanitize a string for safe use inside an AppleScript double-quoted string literal.
    ///
    /// This method:
    /// 1. Enforces a length limit
    /// 2. Removes all control characters (< 0x20) except tab (0x09)
    /// 3. Escapes backslashes, double quotes, and whitespace characters for AppleScript
    ///
    /// - Parameter text: The raw input text.
    /// - Returns: The sanitized string safe for AppleScript interpolation, or nil if the text exceeds the length limit.
    public static func sanitizeForAppleScript(_ text: String) -> String? {
        guard text.count <= maxTextLength else {
            return nil
        }

        // Remove all control characters except tab (0x09).
        // Control characters are those with Unicode value < 0x20.
        let cleaned = String(text.filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            if scalar.value < 0x20 {
                // Allow tab (0x09), remove everything else (including \n 0x0A, \r 0x0D)
                return scalar.value == 0x09
            }
            return true
        })

        // Escape for AppleScript string literal (order matters: backslashes first)
        let escaped = cleaned
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\t", with: "\\t")

        return escaped
    }

    // MARK: - Rate Limiting

    /// Check and update the rate limiter. Returns true if the injection is allowed.
    private func checkRateLimit() -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastInjectionTime)
        if elapsed < TextInjection.minInjectionInterval {
            return false
        }
        lastInjectionTime = now
        return true
    }

    /// Send text to a specific terminal session.
    ///
    /// - Parameters:
    ///   - text: The text to inject into the session.
    ///   - sessionId: The UUID of the TerminalSession to target.
    ///   - pressEnter: If true, appends a newline to execute the text as a command.
    public func sendText(_ text: String, toSession sessionId: String, pressEnter: Bool = true) {
        guard text.count <= TextInjection.maxTextLength else {
            Self.logger.warning("Rejected text: too long (\(text.count) chars)")
            return
        }

        guard checkRateLimit() else {
            Self.logger.warning("Rejected text: rate limit exceeded")
            return
        }

        guard let escapedText = TextInjection.sanitizeForAppleScript(text) else {
            Self.logger.warning("Rejected text: sanitization failed")
            return
        }

        // Build AppleScript targeting the current session of the current window.
        // In future phases, we'll map sessionId to a specific iTerm2 window/session
        // using the windowId-based targeting method below.
        let script: String
        if pressEnter {
            script = """
            tell application "iTerm2"
                tell current session of current window
                    write text "\(escapedText)"
                end tell
            end tell
            """
        } else {
            script = """
            tell application "iTerm2"
                tell current session of current window
                    write text "\(escapedText)" without newline
                end tell
            end tell
            """
        }

        executeAppleScript(script, context: "sendText to session \(sessionId)")
    }

    /// Send text to a specific iTerm2 window identified by its macOS window ID.
    ///
    /// This method enumerates iTerm2's windows to find the one matching the
    /// given windowId (CGWindowID), then targets that window's current session.
    ///
    /// - Parameters:
    ///   - text: The text to inject.
    ///   - windowId: The macOS CGWindowID of the target window.
    ///   - pressEnter: If true, appends a newline to execute the text as a command.
    public func sendText(_ text: String, toWindowId windowId: Int, pressEnter: Bool = true) {
        guard text.count <= TextInjection.maxTextLength else {
            Self.logger.warning("Rejected text: too long (\(text.count) chars)")
            return
        }

        guard checkRateLimit() else {
            Self.logger.warning("Rejected text: rate limit exceeded")
            return
        }

        guard let escapedText = TextInjection.sanitizeForAppleScript(text) else {
            Self.logger.warning("Rejected text: sanitization failed")
            return
        }

        let newlineClause = pressEnter ? "" : " without newline"

        // AppleScript to find the iTerm2 window matching the given window ID
        // and write text to its current session.
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                try
                    if id of w is \(windowId) then
                        tell current session of w
                            write text "\(escapedText)"\(newlineClause)
                        end tell
                        return
                    end if
                end try
            end repeat
            -- Fallback: use current window if no matching window ID found
            tell current session of current window
                write text "\(escapedText)"\(newlineClause)
            end tell
        end tell
        """

        executeAppleScript(script, context: "sendText to windowId \(windowId)")
    }

    /// Send text to all sessions simultaneously.
    ///
    /// - Parameters:
    ///   - text: The text to inject.
    ///   - sessions: The sessions to target.
    ///   - pressEnter: If true, appends a newline to execute the text as a command.
    public func broadcastText(_ text: String, toSessions sessions: [TerminalSession], pressEnter: Bool = true) {
        for session in sessions {
            sendText(text, toWindowId: session.windowId, pressEnter: pressEnter)
        }
    }

    /// List all iTerm2 windows and their IDs for debugging/mapping.
    ///
    /// - Returns: An array of (windowId, name) tuples, or empty if unavailable.
    public func listITermWindows() -> [(id: Int, name: String)] {
        let script = """
        tell application "iTerm2"
            set windowInfo to ""
            repeat with w in windows
                try
                    set windowInfo to windowInfo & (id of w as text) & "|||" & (name of w as text) & "\\n"
                end try
            end repeat
            return windowInfo
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        guard let result = appleScript?.executeAndReturnError(&error) else {
            if let error = error {
                Self.logger.error("listITermWindows error: \(error)")
            }
            return []
        }

        let output = result.stringValue ?? ""
        return output
            .split(separator: "\n")
            .compactMap { line -> (id: Int, name: String)? in
                let parts = line.components(separatedBy: "|||")
                guard parts.count == 2, let id = Int(parts[0]) else { return nil }
                return (id: id, name: parts[1])
            }
    }

    // MARK: - Private

    private func executeAppleScript(_ source: String, context: String) {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: source)
        appleScript?.executeAndReturnError(&error)
        if let error = error {
            Self.logger.error("AppleScript error (\(context)): \(error)")
        }
    }
}
