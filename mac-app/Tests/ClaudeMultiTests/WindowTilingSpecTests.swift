import XCTest
@testable import ClaudeMultiLib

/// # Window Tiling Spec
///
/// Window tiling MUST arrange terminal sessions to fill the screen correctly.
/// Layouts must not leave gaps, must not create overlaps, must respect
/// non-standard screen origins (secondary monitors), and must preserve
/// session identity (id, title, windowId, isSelected) after tiling.
final class WindowTilingSpecTests: XCTestCase {

    private let tiler = WindowTiler()
    private let standardScreen = TerminalSession.SessionBounds(x: 0, y: 0, width: 1920, height: 1080)
    private let accuracy = 0.001

    // MARK: - Helpers

    private func makeSessions(count: Int) -> [TerminalSession] {
        (0..<count).map { i in
            TerminalSession(
                id: "session-\(i)",
                windowId: 100 + i,
                title: "Window \(i)",
                bounds: .init(x: 0, y: 0, width: 100, height: 100),
                isSelected: i == 0
            )
        }
    }

    private func totalArea(_ bounds: [TerminalSession.SessionBounds]) -> Double {
        bounds.reduce(0) { $0 + $1.width * $1.height }
    }

    /// Returns true if any two bounds overlap (share interior area).
    private func hasOverlap(_ bounds: [TerminalSession.SessionBounds]) -> Bool {
        for i in 0..<bounds.count {
            for j in (i + 1)..<bounds.count {
                let a = bounds[i]
                let b = bounds[j]
                let overlapX = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
                let overlapY = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
                if overlapX > accuracy && overlapY > accuracy {
                    return true
                }
            }
        }
        return false
    }

    /// Returns true if every bound is within the screen bounds.
    private func allWithinScreen(
        _ bounds: [TerminalSession.SessionBounds],
        screen: TerminalSession.SessionBounds
    ) -> Bool {
        for b in bounds {
            if b.x < screen.x - accuracy { return false }
            if b.y < screen.y - accuracy { return false }
            if b.x + b.width > screen.x + screen.width + accuracy { return false }
            if b.y + b.height > screen.y + screen.height + accuracy { return false }
        }
        return true
    }

    // =========================================================================
    // MARK: - Tiling 0 sessions MUST return empty array
    // =========================================================================

    func testTiling_0sessions_mustReturnEmpty() {
        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: [], screenBounds: standardScreen)
            XCTAssertTrue(result.isEmpty,
                "\(preset.rawValue) layout with 0 sessions should return empty")
        }
    }

    // =========================================================================
    // MARK: - Tiling 1 session in ANY preset MUST give full screen
    // =========================================================================

    func testTiling_1session_anyPreset_mustFillScreen() {
        let sessions = makeSessions(count: 1)
        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: sessions, screenBounds: standardScreen)
            XCTAssertEqual(result.count, 1, "\(preset.rawValue)")
            XCTAssertEqual(result[0].bounds.x, 0, accuracy: accuracy, "\(preset.rawValue)")
            XCTAssertEqual(result[0].bounds.y, 0, accuracy: accuracy, "\(preset.rawValue)")
            XCTAssertEqual(result[0].bounds.width, 1920, accuracy: accuracy, "\(preset.rawValue)")
            XCTAssertEqual(result[0].bounds.height, 1080, accuracy: accuracy, "\(preset.rawValue)")
        }
    }

    // =========================================================================
    // MARK: - Grid Layout Math
    // =========================================================================

    func testGrid_2sessions_mustBe2x1() {
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 2), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].bounds.width, 960, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.height, 1080, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, 960, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.width, 960, accuracy: accuracy)
    }

    func testGrid_3sessions_mustBe2x2() {
        // ceil(sqrt(3)) = 2 cols, ceil(3/2) = 2 rows
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 3), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 3)
        let cellW = 1920.0 / 2.0
        let cellH = 1080.0 / 2.0
        XCTAssertEqual(result[0].bounds.width, cellW, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.height, cellH, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.x, 0, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.y, cellH, accuracy: accuracy)
    }

    func testGrid_4sessions_mustBe2x2() {
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 4), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 4)
        let cellW = 1920.0 / 2.0
        let cellH = 1080.0 / 2.0
        XCTAssertEqual(result[3].bounds.x, cellW, accuracy: accuracy)
        XCTAssertEqual(result[3].bounds.y, cellH, accuracy: accuracy)
    }

    func testGrid_6sessions_mustBe3x2() {
        // ceil(sqrt(6)) = 3 cols, ceil(6/3) = 2 rows
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 6), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 6)
        let cellW = 1920.0 / 3.0
        let cellH = 1080.0 / 2.0

        // Verify the grid dimensions
        for i in 0..<6 {
            let col = i % 3
            let row = i / 3
            XCTAssertEqual(result[i].bounds.x, Double(col) * cellW, accuracy: accuracy,
                "Session \(i) column offset wrong")
            XCTAssertEqual(result[i].bounds.y, Double(row) * cellH, accuracy: accuracy,
                "Session \(i) row offset wrong")
            XCTAssertEqual(result[i].bounds.width, cellW, accuracy: accuracy,
                "Session \(i) width wrong")
            XCTAssertEqual(result[i].bounds.height, cellH, accuracy: accuracy,
                "Session \(i) height wrong")
        }
    }

    func testGrid_9sessions_mustBe3x3() {
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 9), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 9)
        let cellW = 1920.0 / 3.0
        let cellH = 1080.0 / 3.0
        // Center cell (1,1) = index 4
        XCTAssertEqual(result[4].bounds.x, cellW, accuracy: accuracy)
        XCTAssertEqual(result[4].bounds.y, cellH, accuracy: accuracy)
        XCTAssertEqual(result[4].bounds.width, cellW, accuracy: accuracy)
        XCTAssertEqual(result[4].bounds.height, cellH, accuracy: accuracy)
    }

    // =========================================================================
    // MARK: - Main+Sidebar Layout Math
    // =========================================================================

    func testMainSidebar_2sessions_main60Sidebar40() {
        let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: 2), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 2)
        let mainW = 1920.0 * 0.6
        let sideW = 1920.0 * 0.4
        XCTAssertEqual(result[0].bounds.width, mainW, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.height, 1080, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, mainW, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.width, sideW, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.height, 1080, accuracy: accuracy)
    }

    func testMainSidebar_3sessions_sidebarSplitsHeight() {
        let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: 3), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 3)
        let mainW = 1920.0 * 0.6
        let sideH = 1080.0 / 2.0
        XCTAssertEqual(result[0].bounds.width, mainW, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.height, 1080, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.y, 0, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.height, sideH, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.y, sideH, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.height, sideH, accuracy: accuracy)
    }

    func testMainSidebar_4sessions_threeSidebarsSplitHeight() {
        let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: 4), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 4)
        let sideH = 1080.0 / 3.0
        for i in 1...3 {
            XCTAssertEqual(result[i].bounds.height, sideH, accuracy: accuracy)
            XCTAssertEqual(result[i].bounds.y, Double(i - 1) * sideH, accuracy: accuracy)
        }
    }

    // =========================================================================
    // MARK: - Columns Layout Math
    // =========================================================================

    func testColumns_3sessions_threeEqualWidthColumns() {
        let result = tiler.applyLayout(.columns, to: makeSessions(count: 3), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 3)
        let colW = 1920.0 / 3.0
        for i in 0..<3 {
            XCTAssertEqual(result[i].bounds.x, Double(i) * colW, accuracy: accuracy)
            XCTAssertEqual(result[i].bounds.width, colW, accuracy: accuracy)
            XCTAssertEqual(result[i].bounds.height, 1080, accuracy: accuracy)
        }
    }

    func testColumns_5sessions_fiveEqualWidthColumns() {
        let result = tiler.applyLayout(.columns, to: makeSessions(count: 5), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 5)
        let colW = 1920.0 / 5.0
        for i in 0..<5 {
            XCTAssertEqual(result[i].bounds.width, colW, accuracy: accuracy)
        }
    }

    // =========================================================================
    // MARK: - Rows Layout Math
    // =========================================================================

    func testRows_3sessions_threeEqualHeightRows() {
        let result = tiler.applyLayout(.rows, to: makeSessions(count: 3), screenBounds: standardScreen)
        XCTAssertEqual(result.count, 3)
        let rowH = 1080.0 / 3.0
        for i in 0..<3 {
            XCTAssertEqual(result[i].bounds.y, Double(i) * rowH, accuracy: accuracy)
            XCTAssertEqual(result[i].bounds.width, 1920, accuracy: accuracy)
            XCTAssertEqual(result[i].bounds.height, rowH, accuracy: accuracy)
        }
    }

    // =========================================================================
    // MARK: - Tiling MUST NOT leave gaps (sum of areas = screen area)
    // =========================================================================

    func testColumns_mustNotLeaveGaps() {
        for count in 1...8 {
            let result = tiler.applyLayout(.columns, to: makeSessions(count: count), screenBounds: standardScreen)
            let area = totalArea(result.map(\.bounds))
            let screenArea = standardScreen.width * standardScreen.height
            XCTAssertEqual(area, screenArea, accuracy: accuracy,
                "Columns with \(count) sessions leaves gaps or has overlaps")
        }
    }

    func testRows_mustNotLeaveGaps() {
        for count in 1...8 {
            let result = tiler.applyLayout(.rows, to: makeSessions(count: count), screenBounds: standardScreen)
            let area = totalArea(result.map(\.bounds))
            let screenArea = standardScreen.width * standardScreen.height
            XCTAssertEqual(area, screenArea, accuracy: accuracy,
                "Rows with \(count) sessions leaves gaps or has overlaps")
        }
    }

    func testMainSidebar_mustNotLeaveGaps() {
        for count in 1...6 {
            let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: count), screenBounds: standardScreen)
            let area = totalArea(result.map(\.bounds))
            let screenArea = standardScreen.width * standardScreen.height
            XCTAssertEqual(area, screenArea, accuracy: accuracy,
                "MainSidebar with \(count) sessions leaves gaps or has overlaps")
        }
    }

    func testGrid_placedWindowsArea_mustNotExceedScreenArea() {
        for count in 1...9 {
            let result = tiler.applyLayout(.grid, to: makeSessions(count: count), screenBounds: standardScreen)
            let area = totalArea(result.map(\.bounds))
            let screenArea = standardScreen.width * standardScreen.height
            // Grid may have empty cells, so placed area <= screen area
            XCTAssertLessThanOrEqual(area, screenArea + accuracy,
                "Grid with \(count) sessions exceeds screen area")
        }
    }

    // =========================================================================
    // MARK: - Tiling MUST NOT create overlapping windows
    // =========================================================================

    func testGrid_mustNotCreateOverlaps() {
        for count in 1...9 {
            let result = tiler.applyLayout(.grid, to: makeSessions(count: count), screenBounds: standardScreen)
            XCTAssertFalse(hasOverlap(result.map(\.bounds)),
                "Grid with \(count) sessions has overlapping windows")
        }
    }

    func testColumns_mustNotCreateOverlaps() {
        for count in 1...8 {
            let result = tiler.applyLayout(.columns, to: makeSessions(count: count), screenBounds: standardScreen)
            XCTAssertFalse(hasOverlap(result.map(\.bounds)),
                "Columns with \(count) sessions has overlapping windows")
        }
    }

    func testRows_mustNotCreateOverlaps() {
        for count in 1...8 {
            let result = tiler.applyLayout(.rows, to: makeSessions(count: count), screenBounds: standardScreen)
            XCTAssertFalse(hasOverlap(result.map(\.bounds)),
                "Rows with \(count) sessions has overlapping windows")
        }
    }

    func testMainSidebar_mustNotCreateOverlaps() {
        for count in 1...6 {
            let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: count), screenBounds: standardScreen)
            XCTAssertFalse(hasOverlap(result.map(\.bounds)),
                "MainSidebar with \(count) sessions has overlapping windows")
        }
    }

    // =========================================================================
    // MARK: - All sessions MUST be within screen bounds
    // =========================================================================

    func testAllLayouts_sessionBounds_mustBeWithinScreen() {
        let screens: [(String, TerminalSession.SessionBounds)] = [
            ("standard", standardScreen),
            ("secondary", .init(x: 1920, y: 0, width: 2560, height: 1440)),
            ("left-of-primary", .init(x: -1920, y: 200, width: 1920, height: 1080)),
            ("4K", .init(x: 0, y: 0, width: 3840, height: 2160)),
        ]

        for (screenName, screen) in screens {
            for preset in LayoutPreset.allCases {
                for count in 1...6 {
                    let result = tiler.applyLayout(preset, to: makeSessions(count: count), screenBounds: screen)
                    XCTAssertTrue(allWithinScreen(result.map(\.bounds), screen: screen),
                        "\(preset.rawValue) with \(count) sessions on \(screenName) has windows outside screen bounds")
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Tiling MUST respect screen origin (secondary monitors)
    // =========================================================================

    func testGrid_secondaryMonitorAt1920_mustOffsetCorrectly() {
        let screen = TerminalSession.SessionBounds(x: 1920, y: 0, width: 2560, height: 1440)
        let result = tiler.applyLayout(.grid, to: makeSessions(count: 4), screenBounds: screen)
        let cellW = 2560.0 / 2.0
        let cellH = 1440.0 / 2.0
        XCTAssertEqual(result[0].bounds.x, 1920, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.y, 0, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, 1920 + cellW, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.y, cellH, accuracy: accuracy)
    }

    func testColumns_negativeOrigin_mustOffsetCorrectly() {
        let screen = TerminalSession.SessionBounds(x: -1920, y: 200, width: 1920, height: 1080)
        let result = tiler.applyLayout(.columns, to: makeSessions(count: 3), screenBounds: screen)
        let colW = 1920.0 / 3.0
        XCTAssertEqual(result[0].bounds.x, -1920, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.y, 200, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, -1920 + colW, accuracy: accuracy)
        XCTAssertEqual(result[2].bounds.x, -1920 + 2 * colW, accuracy: accuracy)
    }

    func testRows_negativeOrigin_mustOffsetCorrectly() {
        let screen = TerminalSession.SessionBounds(x: -1920, y: 200, width: 1920, height: 1080)
        let result = tiler.applyLayout(.rows, to: makeSessions(count: 2), screenBounds: screen)
        XCTAssertEqual(result[0].bounds.x, -1920, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.y, 200, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, -1920, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.y, 200 + 540, accuracy: accuracy)
    }

    func testMainSidebar_farRightMonitor_mustOffsetCorrectly() {
        let screen = TerminalSession.SessionBounds(x: 3840, y: 0, width: 2560, height: 1440)
        let result = tiler.applyLayout(.mainSidebar, to: makeSessions(count: 3), screenBounds: screen)
        let mainW = 2560.0 * 0.6
        XCTAssertEqual(result[0].bounds.x, 3840, accuracy: accuracy)
        XCTAssertEqual(result[0].bounds.width, mainW, accuracy: accuracy)
        XCTAssertEqual(result[1].bounds.x, 3840 + mainW, accuracy: accuracy)
    }

    // =========================================================================
    // MARK: - Session identity MUST be preserved after tiling
    // =========================================================================

    func testTiling_mustPreserveSessionId() {
        let sessions = [
            TerminalSession(id: "alpha", windowId: 1, title: "Alpha", bounds: .init(x: 0, y: 0, width: 50, height: 50), isSelected: true),
            TerminalSession(id: "beta", windowId: 2, title: "Beta", bounds: .init(x: 0, y: 0, width: 50, height: 50), isSelected: false),
            TerminalSession(id: "gamma", windowId: 3, title: "Gamma", bounds: .init(x: 0, y: 0, width: 50, height: 50), isSelected: false),
        ]

        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: sessions, screenBounds: standardScreen)
            XCTAssertEqual(result[0].id, "alpha", "\(preset.rawValue) changed session id")
            XCTAssertEqual(result[1].id, "beta", "\(preset.rawValue) changed session id")
            XCTAssertEqual(result[2].id, "gamma", "\(preset.rawValue) changed session id")
        }
    }

    func testTiling_mustPreserveSessionTitle() {
        let sessions = [
            TerminalSession(id: "a", windowId: 1, title: "My Title", bounds: .init(x: 0, y: 0, width: 50, height: 50)),
            TerminalSession(id: "b", windowId: 2, title: "Another Title", bounds: .init(x: 0, y: 0, width: 50, height: 50)),
        ]

        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: sessions, screenBounds: standardScreen)
            XCTAssertEqual(result[0].title, "My Title", "\(preset.rawValue) changed title")
            XCTAssertEqual(result[1].title, "Another Title", "\(preset.rawValue) changed title")
        }
    }

    func testTiling_mustPreserveWindowId() {
        let sessions = [
            TerminalSession(id: "a", windowId: 42, title: "T1", bounds: .init(x: 0, y: 0, width: 50, height: 50)),
            TerminalSession(id: "b", windowId: 99, title: "T2", bounds: .init(x: 0, y: 0, width: 50, height: 50)),
        ]

        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: sessions, screenBounds: standardScreen)
            XCTAssertEqual(result[0].windowId, 42, "\(preset.rawValue) changed windowId")
            XCTAssertEqual(result[1].windowId, 99, "\(preset.rawValue) changed windowId")
        }
    }

    func testTiling_mustPreserveIsSelected() {
        let sessions = [
            TerminalSession(id: "a", windowId: 1, title: "T1", bounds: .init(x: 0, y: 0, width: 50, height: 50), isSelected: true),
            TerminalSession(id: "b", windowId: 2, title: "T2", bounds: .init(x: 0, y: 0, width: 50, height: 50), isSelected: false),
        ]

        for preset in LayoutPreset.allCases {
            let result = tiler.applyLayout(preset, to: sessions, screenBounds: standardScreen)
            XCTAssertTrue(result[0].isSelected, "\(preset.rawValue) changed isSelected")
            XCTAssertFalse(result[1].isSelected, "\(preset.rawValue) changed isSelected")
        }
    }

    // =========================================================================
    // MARK: - LayoutPreset metadata
    // =========================================================================

    func testLayoutPreset_mustHaveFourPresets() {
        XCTAssertEqual(LayoutPreset.allCases.count, 4)
    }

    func testLayoutPreset_displayNames_mustBeHumanReadable() {
        XCTAssertEqual(LayoutPreset.grid.displayName, "Grid")
        XCTAssertEqual(LayoutPreset.mainSidebar.displayName, "Main + Sidebar")
        XCTAssertEqual(LayoutPreset.columns.displayName, "Columns")
        XCTAssertEqual(LayoutPreset.rows.displayName, "Rows")
    }

    func testLayoutPreset_id_mustEqualRawValue() {
        for preset in LayoutPreset.allCases {
            XCTAssertEqual(preset.id, preset.rawValue)
        }
    }
}
