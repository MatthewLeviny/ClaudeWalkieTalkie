import SwiftUI

/// A scaled-down visual preview of the terminal window arrangement on screen.
///
/// Draws rectangles representing each session's bounds, with the selected
/// session highlighted. Uses GeometryReader to fit the preview into the
/// available space while preserving the screen's aspect ratio.
public struct WindowMapPreview: View {
    public let sessions: [TerminalSession]
    public let screenBounds: TerminalSession.SessionBounds
    public let selectedSessionId: String?

    public init(sessions: [TerminalSession], screenBounds: TerminalSession.SessionBounds, selectedSessionId: String?) {
        self.sessions = sessions
        self.screenBounds = screenBounds
        self.selectedSessionId = selectedSessionId
    }

    public var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(availableSize: geometry.size)
            let offsetX = (geometry.size.width - screenBounds.width * scale) / 2
            let offsetY = (geometry.size.height - screenBounds.height * scale) / 2

            ZStack(alignment: .topLeading) {
                // Screen background
                screenBackground(scale: scale, offsetX: offsetX, offsetY: offsetY)

                // Session windows
                ForEach(sessions) { session in
                    SessionTileView(
                        session: session,
                        isSelected: session.id == selectedSessionId,
                        label: sessionLabel(session),
                        dimensionText: dimensionLabel(session)
                    )
                    .frame(
                        width: max(session.bounds.width * scale - 4, 0),
                        height: max(session.bounds.height * scale - 4, 0)
                    )
                    .offset(
                        x: offsetX + (session.bounds.x - screenBounds.x) * scale + 2,
                        y: offsetY + (session.bounds.y - screenBounds.y) * scale + 2
                    )
                }
            }
        }
        .aspectRatio(screenBounds.width / screenBounds.height, contentMode: .fit)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Sub-views

    private func screenBackground(scale: Double, offsetX: Double, offsetY: Double) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.15))
            .frame(
                width: screenBounds.width * scale,
                height: screenBounds.height * scale
            )
            .offset(x: offsetX, y: offsetY)
    }

    // MARK: - Helpers

    private func calculateScale(availableSize: CGSize) -> Double {
        let scaleX = availableSize.width / screenBounds.width
        let scaleY = availableSize.height / screenBounds.height
        return min(scaleX, scaleY)
    }

    private func sessionLabel(_ session: TerminalSession) -> String {
        if let dashIndex = session.title.range(of: " -- ") {
            return String(session.title[dashIndex.upperBound...])
        }
        return session.title
    }

    private func dimensionLabel(_ session: TerminalSession) -> String {
        "\(Int(session.bounds.width))x\(Int(session.bounds.height))"
    }
}

// MARK: - Session Tile Sub-view

/// A single tile in the window map representing one terminal session.
private struct SessionTileView: View {
    let session: TerminalSession
    let isSelected: Bool
    let label: String
    let dimensionText: String

    var body: some View {
        ZStack {
            tileBackground
            tileLabels
        }
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.blue.opacity(0.15))
            .overlay(tileBorder)
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                isSelected ? Color.accentColor : Color.blue.opacity(0.5),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var tileLabels: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(isSelected ? .bold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(dimensionText)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(4)
    }
}
