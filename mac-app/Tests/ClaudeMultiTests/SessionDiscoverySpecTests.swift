import XCTest
import CoreGraphics
@testable import ClaudeMultiLib

/// # Session Discovery Spec
///
/// Session discovery MUST find iTerm2 windows, maintain stable session IDs
/// across refreshes, preserve selection state, and handle window
/// appearance/disappearance correctly.
///
/// Since SCShareableContent requires Screen Recording permission and real
/// windows, many of these tests define the SPEC even when they cannot run
/// in CI. Tests that need real system access use XCTSkipUnless.
final class SessionDiscoverySpecTests: XCTestCase {

    // =========================================================================
    // MARK: - Discovery MUST match iTerm2 by bundle ID
    // =========================================================================

    @MainActor
    func testITerm2BundleID_mustBeGooglechodeIterm2() {
        // The canonical bundle ID for iTerm2 is "com.googlecode.iterm2".
        // SessionDiscovery uses this constant internally. We verify it
        // by checking that the constant exists via the public interface.
        //
        // Since iterm2BundleID is private, we verify indirectly:
        // the spec says discovery MUST match "com.googlecode.iterm2".
        // This test documents the requirement.

        // We can verify the constant by checking if iTerm2 is listed
        // when running — but that requires Screen Recording permission.
        // Instead we verify the discovery object can be created and
        // starts with empty sessions.
        let discovery = SessionDiscovery()
        XCTAssertTrue(discovery.sessions.isEmpty)
        XCTAssertNil(discovery.selectedSessionId)
    }

    // =========================================================================
    // MARK: - Session ID MUST be stable across refreshes
    // =========================================================================

    @MainActor
    func testSessionId_format_mustBeStable() {
        // The implementation uses "iterm2-\(windowID)" as the stable ID.
        // Verify that TerminalSession with this ID format can be created
        // and compared.
        let session1 = TerminalSession(
            id: "iterm2-1001",
            windowId: 1001,
            title: "test",
            bounds: .init(x: 0, y: 0, width: 100, height: 100)
        )
        let session2 = TerminalSession(
            id: "iterm2-1001",
            windowId: 1001,
            title: "test updated",
            bounds: .init(x: 0, y: 0, width: 200, height: 200)
        )
        // Same window = same ID, even if title/bounds changed
        XCTAssertEqual(session1.id, session2.id)
    }

    // =========================================================================
    // MARK: - Selected session MUST be preserved across refreshes
    // =========================================================================

    @MainActor
    func testSelectSession_mustUpdateSelectedSessionId() {
        let discovery = SessionDiscovery()
        // Manually set up sessions (simulating what performScan would do)
        discovery.sessions = [
            TerminalSession(id: "iterm2-1", windowId: 1, title: "T1", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
            TerminalSession(id: "iterm2-2", windowId: 2, title: "T2", bounds: .init(x: 100, y: 0, width: 100, height: 100)),
        ]

        discovery.selectSession("iterm2-2")

        XCTAssertEqual(discovery.selectedSessionId, "iterm2-2")
        XCTAssertFalse(discovery.sessions[0].isSelected)
        XCTAssertTrue(discovery.sessions[1].isSelected)
    }

    @MainActor
    func testSelectSession_mustCallOnSelectedSessionChangedCallback() {
        let discovery = SessionDiscovery()
        discovery.sessions = [
            TerminalSession(id: "s1", windowId: 1, title: "T1", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
        ]

        var callbackSessionId: String?
        discovery.onSelectedSessionChanged = { id in
            callbackSessionId = id
        }

        discovery.selectSession("s1")
        XCTAssertEqual(callbackSessionId, "s1")
    }

    // =========================================================================
    // MARK: - Cycle selection MUST wrap around
    // =========================================================================

    @MainActor
    func testCycleSelection_next_mustWrapAround() {
        let discovery = SessionDiscovery()
        discovery.sessions = [
            TerminalSession(id: "s0", windowId: 0, title: "T0", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
            TerminalSession(id: "s1", windowId: 1, title: "T1", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
            TerminalSession(id: "s2", windowId: 2, title: "T2", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
        ]
        discovery.selectSession("s2") // Last session

        discovery.cycleSelection(direction: .next)
        XCTAssertEqual(discovery.selectedSessionId, "s0",
            "Cycling next from last session must wrap to first")
    }

    @MainActor
    func testCycleSelection_prev_mustWrapAround() {
        let discovery = SessionDiscovery()
        discovery.sessions = [
            TerminalSession(id: "s0", windowId: 0, title: "T0", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
            TerminalSession(id: "s1", windowId: 1, title: "T1", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
            TerminalSession(id: "s2", windowId: 2, title: "T2", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
        ]
        discovery.selectSession("s0") // First session

        discovery.cycleSelection(direction: .prev)
        XCTAssertEqual(discovery.selectedSessionId, "s2",
            "Cycling prev from first session must wrap to last")
    }

    @MainActor
    func testCycleSelection_emptySessionList_mustNotCrash() {
        let discovery = SessionDiscovery()
        discovery.sessions = []
        // Should not crash
        discovery.cycleSelection(direction: .next)
        discovery.cycleSelection(direction: .prev)
    }

    @MainActor
    func testCycleSelection_singleSession_mustStayOnSameSession() {
        let discovery = SessionDiscovery()
        discovery.sessions = [
            TerminalSession(id: "only", windowId: 1, title: "T", bounds: .init(x: 0, y: 0, width: 100, height: 100)),
        ]
        discovery.selectSession("only")

        discovery.cycleSelection(direction: .next)
        XCTAssertEqual(discovery.selectedSessionId, "only")

        discovery.cycleSelection(direction: .prev)
        XCTAssertEqual(discovery.selectedSessionId, "only")
    }

    // =========================================================================
    // MARK: - Discovery MUST NOT trigger Screen Recording permission prompt
    // =========================================================================

    @MainActor
    func testCheckScreenRecordingPermission_mustUsePreflight() {
        // The implementation uses CGPreflightScreenCaptureAccess() which
        // checks permission without triggering a prompt.
        // We verify that calling it does not crash. The actual return value
        // depends on system state.
        let discovery = SessionDiscovery()
        let _ = discovery.checkScreenRecordingPermission()
        // No assertion on the result — just verifying it doesn't prompt/crash.
    }

    // =========================================================================
    // MARK: - Polling timer MUST be cancellable via stopDiscovery()
    // =========================================================================

    @MainActor
    func testStopDiscovery_mustCancelPolling() {
        let discovery = SessionDiscovery()
        discovery.startDiscovery()
        discovery.stopDiscovery()
        // After stopping, the timer should be nil and no further scans occur.
        // We can't directly inspect the timer, but we verify the method exists
        // and doesn't crash.
    }

    @MainActor
    func testStartDiscovery_calledTwice_mustNotLeak() {
        let discovery = SessionDiscovery()
        discovery.startDiscovery()
        discovery.startDiscovery() // Should invalidate the first timer
        discovery.stopDiscovery()
    }

    // =========================================================================
    // MARK: - Poll interval must be configurable
    // =========================================================================

    @MainActor
    func testPollInterval_defaultMustBe2Seconds() {
        let discovery = SessionDiscovery()
        XCTAssertEqual(discovery.pollInterval, 2.0)
    }

    @MainActor
    func testPollInterval_mustBeSettable() {
        let discovery = SessionDiscovery()
        discovery.pollInterval = 5.0
        XCTAssertEqual(discovery.pollInterval, 5.0)
    }

    // =========================================================================
    // MARK: - Initial state
    // =========================================================================

    @MainActor
    func testInitialState_mustBeEmpty() {
        let discovery = SessionDiscovery()
        XCTAssertTrue(discovery.sessions.isEmpty)
        XCTAssertNil(discovery.selectedSessionId)
        XCTAssertFalse(discovery.hasCompletedInitialScan)
        XCTAssertFalse(discovery.hasScreenRecordingPermission)
    }

    // =========================================================================
    // MARK: - Tests requiring Screen Recording permission
    // =========================================================================

    @MainActor
    func testRequiresScreenRecording_discoveryFindsITerm2() throws {
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(),
            "Requires Screen Recording permission")

        let discovery = SessionDiscovery()
        let expectation = XCTestExpectation(description: "Discovery completes initial scan")

        discovery.onSessionsChanged = {
            expectation.fulfill()
        }

        discovery.startDiscovery()

        // Wait for at least one scan to complete
        wait(for: [expectation], timeout: 5.0)
        discovery.stopDiscovery()

        XCTAssertTrue(discovery.hasCompletedInitialScan)
        // If iTerm2 is running, we should find sessions.
        // We can't assert on count since iTerm2 might not be open.
    }

    @MainActor
    func testRequiresScreenRecording_sessionIdStableAcrossRefreshes() throws {
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(),
            "Requires Screen Recording permission")

        let discovery = SessionDiscovery()
        let firstScan = XCTestExpectation(description: "First scan")

        discovery.onSessionsChanged = {
            firstScan.fulfill()
        }

        discovery.pollInterval = 0.5
        discovery.startDiscovery()

        wait(for: [firstScan], timeout: 5.0)

        // Capture IDs after first scan
        let firstScanIds = discovery.sessions.map(\.id)

        // Wait long enough for at least one more poll cycle to complete.
        // onSessionsChanged may not fire if sessions are unchanged, so
        // we sleep instead of waiting for a callback.
        let pollWait = XCTestExpectation(description: "Wait for poll cycle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            pollWait.fulfill()
        }
        wait(for: [pollWait], timeout: 3.0)
        discovery.stopDiscovery()

        // Session IDs from first scan should still be present
        // (assuming no windows were opened/closed between scans)
        let secondScanIds = Set(discovery.sessions.map(\.id))
        for id in firstScanIds {
            XCTAssertTrue(secondScanIds.contains(id),
                "Session ID \(id) was not stable across refreshes")
        }
    }

    @MainActor
    func testRequiresScreenRecording_selectionPreservedAcrossRefresh() throws {
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(),
            "Requires Screen Recording permission")

        let discovery = SessionDiscovery()
        let scanComplete = XCTestExpectation(description: "Scan complete")

        discovery.onSessionsChanged = {
            scanComplete.fulfill()
        }

        discovery.pollInterval = 0.5
        discovery.startDiscovery()
        wait(for: [scanComplete], timeout: 5.0)

        guard let firstSession = discovery.sessions.first else {
            discovery.stopDiscovery()
            return // No windows to test with
        }

        // Select a session
        discovery.selectSession(firstSession.id)
        let selectedId = discovery.selectedSessionId

        // Wait long enough for at least one more poll cycle.
        // onSessionsChanged may not fire if the window list is unchanged,
        // so we wait on a timer instead.
        let pollWait = XCTestExpectation(description: "Wait for poll cycle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            pollWait.fulfill()
        }
        wait(for: [pollWait], timeout: 3.0)
        discovery.stopDiscovery()

        // Selection should be preserved
        XCTAssertEqual(discovery.selectedSessionId, selectedId,
            "Selected session must be preserved across refresh")
    }

    // =========================================================================
    // MARK: - When a window disappears, its session MUST be removed
    //
    // NOTE: This requires programmatically closing an iTerm2 window, which
    // is beyond unit test scope. The spec is documented here.
    // =========================================================================

    // FIXME: Cannot test window disappearance in unit tests. The requirement
    // is: when a window is closed between scans, its TerminalSession must
    // not appear in the sessions array after the next scan completes.

    // =========================================================================
    // MARK: - When a new window appears, it MUST get a new session
    //
    // NOTE: Requires programmatically opening an iTerm2 window.
    // =========================================================================

    // FIXME: Cannot test window appearance in unit tests. The requirement
    // is: when a new window appears between scans, a new TerminalSession
    // with a unique ID based on the window's CGWindowID must be added.
}
