import Foundation

// MARK: - Message Type Enum

/// All supported WebSocket message types in the ClaudeMulti protocol.
public enum MessageType: String, Codable {
    case pair
    case pair_result
    case state_sync
    case selection_changed
    case cycle_selection
    case send_text
    case request_sync
    case error
}

// MARK: - Base Message

/// Fields common to every WebSocket message.
public struct BaseMessage: Codable {
    public let type: MessageType
    public let version: Int

    public init(type: MessageType, version: Int = 1) {
        self.type = type
        self.version = version
    }
}

// MARK: - Specific Message Structs

public struct PairMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let code: String
    public let deviceId: String

    /// Validates that `code` matches the schema pattern `^[0-9]{6}$`.
    public static func isValidCode(_ code: String) -> Bool {
        code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil
    }

    public init(code: String, deviceId: String, version: Int = 1) {
        self.type = .pair
        self.version = version
        self.code = code
        self.deviceId = deviceId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MessageType.self, forKey: .type)
        self.version = try container.decode(Int.self, forKey: .version)
        self.code = try container.decode(String.self, forKey: .code)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)

        guard PairMessage.isValidCode(self.code) else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "Pairing code must match ^[0-9]{6}$, got: \(self.code)"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, version, code, deviceId
    }
}

public struct PairResultMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let success: Bool
    public let message: String?

    public init(success: Bool, message: String? = nil, version: Int = 1) {
        self.type = .pair_result
        self.version = version
        self.success = success
        self.message = message
    }
}

public struct StateSyncMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let sessions: [TerminalSession]
    public let screenBounds: TerminalSession.SessionBounds

    public init(sessions: [TerminalSession], screenBounds: TerminalSession.SessionBounds, version: Int = 1) {
        self.type = .state_sync
        self.version = version
        self.sessions = sessions
        self.screenBounds = screenBounds
    }
}

public struct SelectionChangedMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let selectedSessionId: String

    public init(selectedSessionId: String, version: Int = 1) {
        self.type = .selection_changed
        self.version = version
        self.selectedSessionId = selectedSessionId
    }
}

/// Direction to cycle session selection, matching schema enum: ["next", "prev"].
public enum CycleDirection: String, Codable {
    case next
    case prev
}

public struct CycleSelectionMessage: Codable {
    public let type: MessageType
    public let version: Int
    /// Direction to cycle: `.next` or `.prev`.
    public let direction: CycleDirection

    public init(direction: CycleDirection, version: Int = 1) {
        self.type = .cycle_selection
        self.version = version
        self.direction = direction
    }
}

public struct SendTextMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let text: String
    /// If nil, sends to the currently selected session.
    public let sessionId: String?
    public let pressEnter: Bool

    public init(text: String, sessionId: String? = nil, pressEnter: Bool = true, version: Int = 1) {
        self.type = .send_text
        self.version = version
        self.text = text
        self.sessionId = sessionId
        self.pressEnter = pressEnter
    }
}

public struct RequestSyncMessage: Codable {
    public let type: MessageType
    public let version: Int

    public init(version: Int = 1) {
        self.type = .request_sync
        self.version = version
    }
}

public struct ErrorMessage: Codable {
    public let type: MessageType
    public let version: Int
    public let message: String

    public init(message: String, version: Int = 1) {
        self.type = .error
        self.version = version
        self.message = message
    }
}

// MARK: - Type-Safe Wrapper Enum

/// A type-safe wrapper that decodes any WebSocket message based on its "type" field.
public enum WSMessage: Codable {
    case pair(PairMessage)
    case pairResult(PairResultMessage)
    case stateSync(StateSyncMessage)
    case selectionChanged(SelectionChangedMessage)
    case cycleSelection(CycleSelectionMessage)
    case sendText(SendTextMessage)
    case requestSync(RequestSyncMessage)
    case error(ErrorMessage)

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageType = try container.decode(MessageType.self, forKey: .type)

        let singleValueContainer = try decoder.singleValueContainer()

        switch messageType {
        case .pair:
            self = .pair(try singleValueContainer.decode(PairMessage.self))
        case .pair_result:
            self = .pairResult(try singleValueContainer.decode(PairResultMessage.self))
        case .state_sync:
            self = .stateSync(try singleValueContainer.decode(StateSyncMessage.self))
        case .selection_changed:
            self = .selectionChanged(try singleValueContainer.decode(SelectionChangedMessage.self))
        case .cycle_selection:
            self = .cycleSelection(try singleValueContainer.decode(CycleSelectionMessage.self))
        case .send_text:
            self = .sendText(try singleValueContainer.decode(SendTextMessage.self))
        case .request_sync:
            self = .requestSync(try singleValueContainer.decode(RequestSyncMessage.self))
        case .error:
            self = .error(try singleValueContainer.decode(ErrorMessage.self))
        }
    }

    // MARK: Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pair(let msg):            try container.encode(msg)
        case .pairResult(let msg):      try container.encode(msg)
        case .stateSync(let msg):       try container.encode(msg)
        case .selectionChanged(let msg): try container.encode(msg)
        case .cycleSelection(let msg):  try container.encode(msg)
        case .sendText(let msg):        try container.encode(msg)
        case .requestSync(let msg):     try container.encode(msg)
        case .error(let msg):           try container.encode(msg)
        }
    }
}
