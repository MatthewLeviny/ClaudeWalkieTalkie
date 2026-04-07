import XCTest
@testable import ClaudeMultiLib

/// # Pairing Spec
///
/// Pairing is the security gate between the Mac host and Android companion.
/// It MUST be secure (cryptographically random, 6-digit, zero-padded) and
/// correct (reject wrong codes, store device IDs, block unpaired connections).
///
/// NOTE: WebSocketServer is @MainActor and its pairing logic uses private
/// methods and NWConnection. Some tests verify what we can through the
/// public API; others document what SHOULD be tested but cannot be reached
/// from unit tests without network infrastructure.
final class PairingSpecTests: XCTestCase {

    // =========================================================================
    // MARK: - Pairing code MUST be exactly 6 decimal digits
    // =========================================================================

    @MainActor
    func testPairingCode_mustBe6Digits() {
        let server = WebSocketServer()
        server.start()
        defer { server.stop() }

        guard let code = server.pairingCode else {
            XCTFail("Server must generate a pairing code on start")
            return
        }

        XCTAssertEqual(code.count, 6, "Pairing code must be exactly 6 characters")

        // Every character must be a decimal digit
        let allDigits = code.allSatisfy { $0.isNumber && $0.isASCII }
        XCTAssertTrue(allDigits, "Pairing code must contain only decimal digits, got: \(code)")

        // Must match the schema pattern ^[0-9]{6}$
        let regex = try! NSRegularExpression(pattern: "^[0-9]{6}$")
        let range = NSRange(code.startIndex..., in: code)
        XCTAssertNotNil(regex.firstMatch(in: code, range: range),
            "Pairing code must match ^[0-9]{6}$, got: \(code)")
    }

    // =========================================================================
    // MARK: - Pairing code MUST be cryptographically random (not predictable)
    // =========================================================================

    @MainActor
    func testPairingCode_mustNotBePredictable_generate100UniqueCodes() {
        // Generate 100 codes by starting/stopping the server.
        // All codes should be different (probabilistic test — collision is
        // extremely unlikely with 6-digit codes if the RNG is good).
        var codes = Set<String>()

        for _ in 0..<100 {
            let server = WebSocketServer()
            server.start()
            if let code = server.pairingCode {
                codes.insert(code)
            }
            server.stop()
        }

        // With cryptographic randomness, 100 codes from 1M possible values
        // should all be unique. Allow at most 1 collision as a safety margin.
        XCTAssertGreaterThanOrEqual(codes.count, 99,
            "100 generated pairing codes should be nearly all unique; got \(codes.count) unique codes")
    }

    // =========================================================================
    // MARK: - Pairing code MUST be zero-padded
    // =========================================================================

    @MainActor
    func testPairingCode_mustAlwaysBe6Characters() {
        // Even codes like 000123 must be zero-padded to 6 digits.
        // We generate many codes and verify none are shorter than 6.
        for _ in 0..<50 {
            let server = WebSocketServer()
            server.start()
            if let code = server.pairingCode {
                XCTAssertEqual(code.count, 6,
                    "Pairing code must be zero-padded to 6 digits, got: \(code)")
            }
            server.stop()
        }
    }

    // =========================================================================
    // MARK: - Server lifecycle
    // =========================================================================

    @MainActor
    func testServer_start_mustGeneratePairingCode() {
        let server = WebSocketServer()
        XCTAssertNil(server.pairingCode, "Code should be nil before start")

        server.start()
        XCTAssertNotNil(server.pairingCode, "Code must be generated on start")

        server.stop()
        XCTAssertNil(server.pairingCode, "Code must be cleared on stop")
    }

    @MainActor
    func testServer_stop_mustClearState() {
        let server = WebSocketServer()
        server.start()
        server.stop()

        XCTAssertFalse(server.isRunning)
        XCTAssertEqual(server.connectedClients, 0)
        XCTAssertNil(server.pairingCode)
    }

    @MainActor
    func testServer_defaultPort_mustBe8765() {
        XCTAssertEqual(WebSocketServer.defaultPort, 8765)
    }

    // =========================================================================
    // MARK: - Incorrect pairing code MUST be rejected
    //
    // NOTE: Testing the actual pairing flow requires creating a real
    // NWConnection and exchanging WebSocket frames. The following tests
    // verify the protocol message structure used for rejection.
    // =========================================================================

    func testPairResultMessage_rejection_hasCorrectStructure() throws {
        let result = PairResultMessage(success: false, message: "Invalid pairing code")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PairResultMessage.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.message, "Invalid pairing code")
        XCTAssertEqual(decoded.type, .pair_result)
        XCTAssertEqual(decoded.version, 1)
    }

    func testPairResultMessage_success_hasCorrectStructure() throws {
        let result = PairResultMessage(success: true, message: "Paired successfully")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PairResultMessage.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "Paired successfully")
    }

    // =========================================================================
    // MARK: - Device IDs MUST be stored after successful pairing
    //
    // The server stores paired device IDs in UserDefaults under
    // "ClaudeMulti.pairedDeviceIds". This is a private property, so we
    // document what SHOULD be tested.
    // =========================================================================

    // SHOULD test: After a successful pair, the device ID is in UserDefaults.
    // SHOULD test: After a failed pair, the device ID is NOT in UserDefaults.
    // SHOULD test: Unpaired connections receive {"type":"error","message":"not paired"}.

    func testPairMessage_canEncodeDeviceId() throws {
        // At minimum, verify the PairMessage carries the deviceId correctly.
        let msg = PairMessage(code: "123456", deviceId: "my-pixel-device")
        let data = try JSONEncoder().encode(msg)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["deviceId"] as? String, "my-pixel-device")
    }

    // =========================================================================
    // MARK: - Unpaired connections MUST NOT be able to send commands
    //
    // The server's handleTextMessage checks connectionDeviceIds before
    // dispatching. Without a paired connection, it sends an error message.
    // We verify the error message structure here.
    // =========================================================================

    func testUnpairedError_message_mustBeNotPaired() throws {
        let errorMsg = ErrorMessage(message: "not paired")
        let wsMsg = WSMessage.error(errorMsg)
        let data = try JSONEncoder().encode(wsMsg)
        let decoded = try JSONDecoder().decode(WSMessage.self, from: data)

        if case .error(let e) = decoded {
            XCTAssertEqual(e.message, "not paired")
        } else {
            XCTFail("Expected .error case")
        }
    }

    // =========================================================================
    // MARK: - Previously paired device SHOULD reconnect without re-pairing
    //
    // SHOULD test: A device whose ID is in pairedDeviceIds can send commands
    // immediately after connecting, without exchanging a new pair message.
    //
    // NOTE: This requires creating a real NWConnection with a mock device ID
    // already in UserDefaults. The auth token flow is handled inside
    // WebSocketServer.handleTextMessage which is private.
    // =========================================================================

    // FIXME: The reconnection flow for previously-paired devices is not
    // testable through the public API. The server checks pairedDeviceIds
    // (persisted in UserDefaults) against connectionDeviceIds (set during
    // handlePairMessage). A reconnecting device would need to send a new
    // pair message — there is no separate "auth token" flow yet.
    // This test documents the gap.

    @MainActor
    func testReconnection_noAuthTokenFlowExists() {
        // Document: currently there is no way for a previously-paired device
        // to skip the pairing step. The connectionDeviceIds map is cleared
        // on server stop, so the device must re-pair each session.
        let server = WebSocketServer()
        server.start()
        server.stop()

        // After stop, the connection state is fully cleared
        XCTAssertEqual(server.connectedClients, 0)
        // FIXME: A reconnection/auth-token mechanism should be implemented
        // so previously paired devices don't need to re-pair every session.
    }
}
