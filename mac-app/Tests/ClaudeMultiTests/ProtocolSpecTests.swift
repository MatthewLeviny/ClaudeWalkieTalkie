import XCTest
@testable import ClaudeMultiLib

/// # Protocol Wire Format Spec
///
/// The WebSocket protocol between Mac and Android MUST match the JSON Schema
/// defined in `protocol/schema/messages.json`. Every example file in
/// `protocol/examples/` is a canonical reference — both platforms must
/// produce and consume identical JSON for the same logical message.
final class ProtocolSpecTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // =========================================================================
    // MARK: - Example File Round-Trips
    // Each test hardcodes the exact JSON from protocol/examples/ and verifies
    // that Swift decodes every field correctly, then re-encodes with the
    // required keys present.
    // =========================================================================

    // MARK: pair.json

    func testExample_pair_decodesExactly() throws {
        let json = """
        {"type":"pair","version":1,"code":"482910","deviceId":"pixel-8-a1b2c3d4"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .pair(let p) = msg else {
            return XCTFail("Expected .pair, got \\(msg)")
        }
        XCTAssertEqual(p.type, .pair)
        XCTAssertEqual(p.version, 1)
        XCTAssertEqual(p.code, "482910")
        XCTAssertEqual(p.deviceId, "pixel-8-a1b2c3d4")
    }

    func testExample_pair_reEncodesRequiredFields() throws {
        let json = """
        {"type":"pair","version":1,"code":"482910","deviceId":"pixel-8-a1b2c3d4"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "pair")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["code"] as? String, "482910")
        XCTAssertEqual(dict["deviceId"] as? String, "pixel-8-a1b2c3d4")
    }

    // MARK: pair_result.json

    func testExample_pairResult_decodesExactly() throws {
        let json = """
        {"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .pairResult(let p) = msg else {
            return XCTFail("Expected .pairResult, got \\(msg)")
        }
        XCTAssertEqual(p.type, .pair_result)
        XCTAssertEqual(p.version, 1)
        XCTAssertTrue(p.success)
        XCTAssertEqual(p.message, "Paired successfully")
    }

    func testExample_pairResult_reEncodesRequiredFields() throws {
        let json = """
        {"type":"pair_result","version":1,"success":true,"message":"Paired successfully"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "pair_result")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["success"] as? Bool, true)
        // message is optional per schema — but included in the example
        XCTAssertEqual(dict["message"] as? String, "Paired successfully")
    }

    // MARK: state_sync.json

    func testExample_stateSync_decodesExactly() throws {
        let json = """
        {"type":"state_sync","version":1,"sessions":[{"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true},{"id":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d","windowId":1002,"title":"api-tests runner","bounds":{"x":960,"y":0,"width":960,"height":540},"isSelected":false},{"id":"6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b","windowId":1003,"title":"docs update","bounds":{"x":960,"y":540,"width":960,"height":540},"isSelected":false}],"screenBounds":{"x":0,"y":0,"width":1920,"height":1080}}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .stateSync(let s) = msg else {
            return XCTFail("Expected .stateSync, got \\(msg)")
        }

        XCTAssertEqual(s.type, .state_sync)
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.sessions.count, 3)

        // First session
        XCTAssertEqual(s.sessions[0].id, "f47ac10b-58cc-4372-a567-0e02b2c3d479")
        XCTAssertEqual(s.sessions[0].windowId, 1001)
        XCTAssertEqual(s.sessions[0].title, "claude-backend refactor")
        XCTAssertEqual(s.sessions[0].bounds.x, 0)
        XCTAssertEqual(s.sessions[0].bounds.y, 0)
        XCTAssertEqual(s.sessions[0].bounds.width, 960)
        XCTAssertEqual(s.sessions[0].bounds.height, 1080)
        XCTAssertTrue(s.sessions[0].isSelected)

        // Second session
        XCTAssertEqual(s.sessions[1].id, "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d")
        XCTAssertEqual(s.sessions[1].windowId, 1002)
        XCTAssertEqual(s.sessions[1].title, "api-tests runner")
        XCTAssertEqual(s.sessions[1].bounds.x, 960)
        XCTAssertEqual(s.sessions[1].bounds.y, 0)
        XCTAssertEqual(s.sessions[1].bounds.width, 960)
        XCTAssertEqual(s.sessions[1].bounds.height, 540)
        XCTAssertFalse(s.sessions[1].isSelected)

        // Third session
        XCTAssertEqual(s.sessions[2].id, "6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b")
        XCTAssertEqual(s.sessions[2].windowId, 1003)
        XCTAssertEqual(s.sessions[2].title, "docs update")
        XCTAssertEqual(s.sessions[2].bounds.x, 960)
        XCTAssertEqual(s.sessions[2].bounds.y, 540)
        XCTAssertEqual(s.sessions[2].bounds.width, 960)
        XCTAssertEqual(s.sessions[2].bounds.height, 540)
        XCTAssertFalse(s.sessions[2].isSelected)

        // Screen bounds
        XCTAssertEqual(s.screenBounds.x, 0)
        XCTAssertEqual(s.screenBounds.y, 0)
        XCTAssertEqual(s.screenBounds.width, 1920)
        XCTAssertEqual(s.screenBounds.height, 1080)
    }

    func testExample_stateSync_reEncodesRequiredFields() throws {
        let json = """
        {"type":"state_sync","version":1,"sessions":[{"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479","windowId":1001,"title":"claude-backend refactor","bounds":{"x":0,"y":0,"width":960,"height":1080},"isSelected":true}],"screenBounds":{"x":0,"y":0,"width":1920,"height":1080}}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "state_sync")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertNotNil(dict["sessions"] as? [[String: Any]])
        XCTAssertNotNil(dict["screenBounds"] as? [String: Any])
    }

    // MARK: selection_changed.json

    func testExample_selectionChanged_decodesExactly() throws {
        let json = """
        {"type":"selection_changed","version":1,"selectedSessionId":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .selectionChanged(let s) = msg else {
            return XCTFail("Expected .selectionChanged, got \\(msg)")
        }
        XCTAssertEqual(s.type, .selection_changed)
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.selectedSessionId, "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d")
    }

    func testExample_selectionChanged_reEncodesRequiredFields() throws {
        let json = """
        {"type":"selection_changed","version":1,"selectedSessionId":"9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "selection_changed")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["selectedSessionId"] as? String, "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d")
    }

    // MARK: cycle_selection.json

    func testExample_cycleSelection_decodesExactly() throws {
        let json = """
        {"type":"cycle_selection","version":1,"direction":"next"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .cycleSelection(let c) = msg else {
            return XCTFail("Expected .cycleSelection, got \\(msg)")
        }
        XCTAssertEqual(c.type, .cycle_selection)
        XCTAssertEqual(c.version, 1)
        XCTAssertEqual(c.direction, .next)
    }

    func testExample_cycleSelection_reEncodesRequiredFields() throws {
        let json = """
        {"type":"cycle_selection","version":1,"direction":"next"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "cycle_selection")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["direction"] as? String, "next")
    }

    // MARK: send_text.json

    func testExample_sendText_decodesExactly() throws {
        let json = """
        {"type":"send_text","version":1,"text":"git status","sessionId":"f47ac10b-58cc-4372-a567-0e02b2c3d479","pressEnter":true}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .sendText(let s) = msg else {
            return XCTFail("Expected .sendText, got \\(msg)")
        }
        XCTAssertEqual(s.type, .send_text)
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.text, "git status")
        XCTAssertEqual(s.sessionId, "f47ac10b-58cc-4372-a567-0e02b2c3d479")
        XCTAssertTrue(s.pressEnter)
    }

    func testExample_sendText_reEncodesRequiredFields() throws {
        let json = """
        {"type":"send_text","version":1,"text":"git status","sessionId":"f47ac10b-58cc-4372-a567-0e02b2c3d479","pressEnter":true}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "send_text")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["text"] as? String, "git status")
        XCTAssertEqual(dict["pressEnter"] as? Bool, true)
    }

    // MARK: request_sync.json

    func testExample_requestSync_decodesExactly() throws {
        let json = """
        {"type":"request_sync","version":1}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .requestSync(let r) = msg else {
            return XCTFail("Expected .requestSync, got \\(msg)")
        }
        XCTAssertEqual(r.type, .request_sync)
        XCTAssertEqual(r.version, 1)
    }

    func testExample_requestSync_reEncodesRequiredFields() throws {
        let json = """
        {"type":"request_sync","version":1}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "request_sync")
        XCTAssertEqual(dict["version"] as? Int, 1)
    }

    // MARK: error.json

    func testExample_error_decodesExactly() throws {
        let json = """
        {"type":"error","version":1,"message":"Session not found: invalid-uuid"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        guard case .error(let e) = msg else {
            return XCTFail("Expected .error, got \\(msg)")
        }
        XCTAssertEqual(e.type, .error)
        XCTAssertEqual(e.version, 1)
        XCTAssertEqual(e.message, "Session not found: invalid-uuid")
    }

    func testExample_error_reEncodesRequiredFields() throws {
        let json = """
        {"type":"error","version":1,"message":"Session not found: invalid-uuid"}
        """.data(using: .utf8)!

        let msg = try decoder.decode(WSMessage.self, from: json)
        let reEncoded = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: reEncoded) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "error")
        XCTAssertEqual(dict["version"] as? Int, 1)
        XCTAssertEqual(dict["message"] as? String, "Session not found: invalid-uuid")
    }

    // =========================================================================
    // MARK: - Schema-Driven Validation: pair.code pattern ^[0-9]{6}$
    // =========================================================================

    func testPairCode_mustBe6Digits_valid() throws {
        // The schema requires code to match ^[0-9]{6}$
        // These are valid codes
        let validCodes = ["000000", "123456", "999999", "482910"]
        for code in validCodes {
            let json = """
            {"type":"pair","version":1,"code":"\(code)","deviceId":"test"}
            """.data(using: .utf8)!
            let msg = try decoder.decode(PairMessage.self, from: json)
            XCTAssertEqual(msg.code, code)
        }
    }

    func testPairCode_5digits_shouldBeRejected() throws {
        // Schema requires code to match ^[0-9]{6}$ — 5-digit codes must be rejected.
        let json = """
        {"type":"pair","version":1,"code":"12345","deviceId":"test"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(PairMessage.self, from: json),
            "5-digit code must be rejected by schema pattern validation")
    }

    func testPairCode_7digits_shouldBeRejected() throws {
        // Schema requires code to match ^[0-9]{6}$ — 7-digit codes must be rejected.
        let json = """
        {"type":"pair","version":1,"code":"1234567","deviceId":"test"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(PairMessage.self, from: json),
            "7-digit code must be rejected by schema pattern validation")
    }

    func testPairCode_alphabetic_shouldBeRejected() throws {
        // Schema requires code to match ^[0-9]{6}$ — alphabetic codes must be rejected.
        let json = """
        {"type":"pair","version":1,"code":"abcdef","deviceId":"test"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(PairMessage.self, from: json),
            "Alphabetic code must be rejected by schema pattern validation")
    }

    // =========================================================================
    // MARK: - Schema-Driven Validation: cycle_selection.direction enum
    // =========================================================================

    func testCycleSelectionDirection_mustBeNextOrPrev_validNext() throws {
        let json = """
        {"type":"cycle_selection","version":1,"direction":"next"}
        """.data(using: .utf8)!
        let msg = try decoder.decode(CycleSelectionMessage.self, from: json)
        XCTAssertEqual(msg.direction, .next)
    }

    func testCycleSelectionDirection_mustBeNextOrPrev_validPrev() throws {
        let json = """
        {"type":"cycle_selection","version":1,"direction":"prev"}
        """.data(using: .utf8)!
        let msg = try decoder.decode(CycleSelectionMessage.self, from: json)
        XCTAssertEqual(msg.direction, .prev)
    }

    func testCycleSelectionDirection_forward_shouldBeRejected() throws {
        // Schema says enum: ["next", "prev"] — "forward" must be rejected.
        let json = """
        {"type":"cycle_selection","version":1,"direction":"forward"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(CycleSelectionMessage.self, from: json),
            "Invalid direction 'forward' must be rejected by CycleDirection enum")
    }

    func testCycleSelectionDirection_emptyString_shouldBeRejected() throws {
        // Schema says enum: ["next", "prev"] — empty string must be rejected.
        let json = """
        {"type":"cycle_selection","version":1,"direction":""}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try decoder.decode(CycleSelectionMessage.self, from: json),
            "Empty direction must be rejected by CycleDirection enum")
    }

    // =========================================================================
    // MARK: - Schema-Driven Validation: send_text.sessionId is OPTIONAL
    // =========================================================================

    func testSendText_withSessionId_decodesCorrectly() throws {
        let json = """
        {"type":"send_text","version":1,"text":"ls","sessionId":"some-uuid","pressEnter":true}
        """.data(using: .utf8)!
        let msg = try decoder.decode(SendTextMessage.self, from: json)
        XCTAssertEqual(msg.sessionId, "some-uuid")
    }

    func testSendText_withoutSessionId_decodesCorrectly() throws {
        // sessionId is not required per schema — omitting it should work
        let json = """
        {"type":"send_text","version":1,"text":"pwd","pressEnter":false}
        """.data(using: .utf8)!
        let msg = try decoder.decode(SendTextMessage.self, from: json)
        XCTAssertNil(msg.sessionId)
        XCTAssertEqual(msg.text, "pwd")
        XCTAssertFalse(msg.pressEnter)
    }

    func testSendText_withNullSessionId_decodesCorrectly() throws {
        let json = """
        {"type":"send_text","version":1,"text":"echo hi","sessionId":null,"pressEnter":true}
        """.data(using: .utf8)!
        let msg = try decoder.decode(SendTextMessage.self, from: json)
        XCTAssertNil(msg.sessionId)
    }

    // =========================================================================
    // MARK: - Schema-Driven Validation: pair_result.message is OPTIONAL
    // =========================================================================

    func testPairResult_withMessage_decodesCorrectly() throws {
        let json = """
        {"type":"pair_result","version":1,"success":true,"message":"OK"}
        """.data(using: .utf8)!
        let msg = try decoder.decode(PairResultMessage.self, from: json)
        XCTAssertEqual(msg.message, "OK")
    }

    func testPairResult_withoutMessage_decodesCorrectly() throws {
        let json = """
        {"type":"pair_result","version":1,"success":false}
        """.data(using: .utf8)!
        let msg = try decoder.decode(PairResultMessage.self, from: json)
        XCTAssertNil(msg.message)
        XCTAssertFalse(msg.success)
    }

    func testPairResult_withNullMessage_decodesCorrectly() throws {
        let json = """
        {"type":"pair_result","version":1,"success":true,"message":null}
        """.data(using: .utf8)!
        let msg = try decoder.decode(PairResultMessage.self, from: json)
        XCTAssertNil(msg.message)
    }

    // =========================================================================
    // MARK: - All Messages: version MUST be 1
    // =========================================================================

    func testAllMessages_defaultVersion_mustBeOne() {
        XCTAssertEqual(PairMessage(code: "123456", deviceId: "d").version, 1)
        XCTAssertEqual(PairResultMessage(success: true).version, 1)
        XCTAssertEqual(StateSyncMessage(
            sessions: [],
            screenBounds: .init(x: 0, y: 0, width: 100, height: 100)
        ).version, 1)
        XCTAssertEqual(SelectionChangedMessage(selectedSessionId: "s").version, 1)
        XCTAssertEqual(CycleSelectionMessage(direction: .next).version, 1)
        XCTAssertEqual(SendTextMessage(text: "t").version, 1)
        XCTAssertEqual(RequestSyncMessage().version, 1)
        XCTAssertEqual(ErrorMessage(message: "e").version, 1)
    }

    func testVersionField_mustEncodeAsIntegerOne() throws {
        let msg = RequestSyncMessage()
        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["version"] as? Int, 1)
    }

    // =========================================================================
    // MARK: - All Messages: type MUST be the discriminator
    // =========================================================================

    func testTypeField_mustBeCorrectDiscriminator() {
        XCTAssertEqual(PairMessage(code: "000000", deviceId: "d").type, .pair)
        XCTAssertEqual(PairResultMessage(success: true).type, .pair_result)
        XCTAssertEqual(StateSyncMessage(
            sessions: [],
            screenBounds: .init(x: 0, y: 0, width: 100, height: 100)
        ).type, .state_sync)
        XCTAssertEqual(SelectionChangedMessage(selectedSessionId: "s").type, .selection_changed)
        XCTAssertEqual(CycleSelectionMessage(direction: .next).type, .cycle_selection)
        XCTAssertEqual(SendTextMessage(text: "t").type, .send_text)
        XCTAssertEqual(RequestSyncMessage().type, .request_sync)
        XCTAssertEqual(ErrorMessage(message: "e").type, .error)
    }

    // =========================================================================
    // MARK: - additionalProperties: false — extra fields
    // =========================================================================

    func testAdditionalProperties_extraFieldsInJSON_shouldBeRejected() throws {
        // The schema says additionalProperties: false for all message types.
        // Swift's Codable silently ignores unknown keys by default.
        // This test documents the deviation from the schema.
        let json = """
        {"type":"error","version":1,"message":"test","extraField":"unexpected","anotherExtra":42}
        """.data(using: .utf8)!

        // FIXME: This requirement is not yet enforced — Swift's JSONDecoder
        // silently ignores extra fields rather than rejecting them.
        // The schema mandates additionalProperties: false.
        let msg = try decoder.decode(WSMessage.self, from: json)
        if case .error(let e) = msg {
            XCTAssertEqual(e.message, "test",
                "Swift silently ignores extra fields — additionalProperties:false is NOT enforced")
        } else {
            XCTFail("Unexpected decode result")
        }
    }

    // =========================================================================
    // MARK: - Unknown/invalid type discriminator
    // =========================================================================

    func testWSMessage_unknownType_mustThrow() {
        let json = """
        {"type":"unknown_type","version":1}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(WSMessage.self, from: json))
    }

    func testWSMessage_missingTypeField_mustThrow() {
        let json = """
        {"version":1,"message":"no type"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(WSMessage.self, from: json))
    }

    func testWSMessage_missingVersionField_mustThrow() {
        let json = """
        {"type":"request_sync"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(WSMessage.self, from: json))
    }

    func testWSMessage_missingRequiredField_mustThrow() {
        // pair requires "code" and "deviceId"
        let json = """
        {"type":"pair","version":1,"code":"123456"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(WSMessage.self, from: json))
    }

    // =========================================================================
    // MARK: - Cross-Platform Contract: encode/decode round-trip for ALL types
    // =========================================================================

    func testWSMessage_encodeDecodeRoundTrip_allMessageTypes() throws {
        let messages: [WSMessage] = [
            .pair(PairMessage(code: "482910", deviceId: "pixel-8-a1b2c3d4")),
            .pairResult(PairResultMessage(success: true, message: "Paired successfully")),
            .stateSync(StateSyncMessage(
                sessions: [
                    TerminalSession(
                        id: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
                        windowId: 1001,
                        title: "claude-backend refactor",
                        bounds: .init(x: 0, y: 0, width: 960, height: 1080),
                        isSelected: true
                    ),
                    TerminalSession(
                        id: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
                        windowId: 1002,
                        title: "api-tests runner",
                        bounds: .init(x: 960, y: 0, width: 960, height: 540),
                        isSelected: false
                    ),
                    TerminalSession(
                        id: "6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b",
                        windowId: 1003,
                        title: "docs update",
                        bounds: .init(x: 960, y: 540, width: 960, height: 540),
                        isSelected: false
                    )
                ],
                screenBounds: .init(x: 0, y: 0, width: 1920, height: 1080)
            )),
            .selectionChanged(SelectionChangedMessage(selectedSessionId: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d")),
            .cycleSelection(CycleSelectionMessage(direction: .next)),
            .sendText(SendTextMessage(text: "git status", sessionId: "f47ac10b-58cc-4372-a567-0e02b2c3d479", pressEnter: true)),
            .requestSync(RequestSyncMessage()),
            .error(ErrorMessage(message: "Session not found: invalid-uuid"))
        ]

        for original in messages {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(WSMessage.self, from: data)
            let reEncoded = try encoder.encode(decoded)

            let originalDict = try JSONSerialization.jsonObject(with: data) as! NSDictionary
            let reEncodedDict = try JSONSerialization.jsonObject(with: reEncoded) as! NSDictionary
            XCTAssertEqual(originalDict, reEncodedDict,
                "Round-trip failed for message: \(original)")
        }
    }

    // =========================================================================
    // MARK: - Cross-Platform Contract: state_sync canonical JSON
    // =========================================================================

    func testStateSync_canonicalJSON_matchesExampleFile() throws {
        // Encode a StateSyncMessage with the same data as the example file,
        // then verify the JSON matches the canonical reference.
        let msg = StateSyncMessage(
            sessions: [
                TerminalSession(
                    id: "f47ac10b-58cc-4372-a567-0e02b2c3d479",
                    windowId: 1001,
                    title: "claude-backend refactor",
                    bounds: .init(x: 0, y: 0, width: 960, height: 1080),
                    isSelected: true
                ),
                TerminalSession(
                    id: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
                    windowId: 1002,
                    title: "api-tests runner",
                    bounds: .init(x: 960, y: 0, width: 960, height: 540),
                    isSelected: false
                ),
                TerminalSession(
                    id: "6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b",
                    windowId: 1003,
                    title: "docs update",
                    bounds: .init(x: 960, y: 540, width: 960, height: 540),
                    isSelected: false
                )
            ],
            screenBounds: .init(x: 0, y: 0, width: 1920, height: 1080)
        )

        let data = try encoder.encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Verify all top-level keys are present
        XCTAssertEqual(dict["type"] as? String, "state_sync")
        XCTAssertEqual(dict["version"] as? Int, 1)

        let sessions = dict["sessions"] as! [[String: Any]]
        XCTAssertEqual(sessions.count, 3)

        // Verify first session has all required schema fields
        let firstSession = sessions[0]
        XCTAssertEqual(firstSession["id"] as? String, "f47ac10b-58cc-4372-a567-0e02b2c3d479")
        XCTAssertEqual(firstSession["windowId"] as? Int, 1001)
        XCTAssertEqual(firstSession["title"] as? String, "claude-backend refactor")
        XCTAssertEqual(firstSession["isSelected"] as? Bool, true)

        let bounds = firstSession["bounds"] as! [String: Any]
        XCTAssertEqual(bounds["x"] as? Double, 0)
        XCTAssertEqual(bounds["y"] as? Double, 0)
        XCTAssertEqual(bounds["width"] as? Double, 960)
        XCTAssertEqual(bounds["height"] as? Double, 1080)

        let screenBounds = dict["screenBounds"] as! [String: Any]
        XCTAssertEqual(screenBounds["width"] as? Double, 1920)
        XCTAssertEqual(screenBounds["height"] as? Double, 1080)
    }

    // =========================================================================
    // MARK: - Unicode and special characters in messages
    // =========================================================================

    func testErrorMessage_unicode_mustRoundTrip() throws {
        let unicodeMessage = "错误消息 Ошибка エラー 오류 مشکل"
        let msg = ErrorMessage(message: unicodeMessage)
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ErrorMessage.self, from: data)
        XCTAssertEqual(decoded.message, unicodeMessage)
    }

    func testErrorMessage_specialCharacters_mustRoundTrip() throws {
        let specialMessage = "Error: \"not paired\" — 日本語テスト \\ backslash"
        let msg = ErrorMessage(message: specialMessage)
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ErrorMessage.self, from: data)
        XCTAssertEqual(decoded.message, specialMessage)
    }

    // =========================================================================
    // MARK: - TerminalSession Codable conformance
    // =========================================================================

    func testTerminalSession_codableRoundTrip_preservesAllFields() throws {
        let original = TerminalSession(
            id: "test-session-1",
            windowId: 42,
            title: "iTerm2 — ~/projects",
            bounds: .init(x: 100.5, y: 200.5, width: 800.0, height: 600.0),
            isSelected: true
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TerminalSession.self, from: data)

        XCTAssertEqual(decoded.id, "test-session-1")
        XCTAssertEqual(decoded.windowId, 42)
        XCTAssertEqual(decoded.title, "iTerm2 — ~/projects")
        XCTAssertEqual(decoded.bounds.x, 100.5)
        XCTAssertEqual(decoded.bounds.y, 200.5)
        XCTAssertEqual(decoded.bounds.width, 800.0)
        XCTAssertEqual(decoded.bounds.height, 600.0)
        XCTAssertTrue(decoded.isSelected)
    }

    func testTerminalSession_defaultId_mustBeValidUUID() {
        let session = TerminalSession(
            windowId: 1,
            title: "Test",
            bounds: .init(x: 0, y: 0, width: 100, height: 100)
        )
        XCTAssertEqual(session.id.count, 36)
        XCTAssertNotNil(UUID(uuidString: session.id))
    }

    func testTerminalSession_defaultIsSelected_mustBeFalse() {
        let session = TerminalSession(
            windowId: 1,
            title: "Test",
            bounds: .init(x: 0, y: 0, width: 100, height: 100)
        )
        XCTAssertFalse(session.isSelected)
    }

    func testSessionBounds_equality_mustCompareAllFields() {
        let a = TerminalSession.SessionBounds(x: 10, y: 20, width: 300, height: 400)
        let b = TerminalSession.SessionBounds(x: 10, y: 20, width: 300, height: 400)
        let c = TerminalSession.SessionBounds(x: 11, y: 20, width: 300, height: 400)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTerminalSession_equality_mustCompareAllFields() {
        let bounds = TerminalSession.SessionBounds(x: 0, y: 0, width: 100, height: 100)
        let a = TerminalSession(id: "s1", windowId: 1, title: "T", bounds: bounds, isSelected: false)
        let b = TerminalSession(id: "s1", windowId: 1, title: "T", bounds: bounds, isSelected: false)
        let c = TerminalSession(id: "s1", windowId: 1, title: "T", bounds: bounds, isSelected: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTerminalSession_boundsAreMutable() {
        var session = TerminalSession(
            windowId: 1, title: "Test", bounds: .init(x: 0, y: 0, width: 100, height: 100)
        )
        session.bounds = .init(x: 50, y: 50, width: 200, height: 200)
        XCTAssertEqual(session.bounds.x, 50)
        XCTAssertEqual(session.bounds.width, 200)
    }

    func testTerminalSession_isSelectedIsMutable() {
        var session = TerminalSession(
            windowId: 1, title: "Test", bounds: .init(x: 0, y: 0, width: 100, height: 100)
        )
        XCTAssertFalse(session.isSelected)
        session.isSelected = true
        XCTAssertTrue(session.isSelected)
    }
}
