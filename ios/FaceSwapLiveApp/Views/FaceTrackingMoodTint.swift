import SwiftUI

extension FaceTrackingMood {
    /// The colour the pill button, the tucked tab and the status capsule wear.
    var tint: Color {
        switch self {
        case .off, .waiting: .white.opacity(0.45)
        case .searching: .orange
        case .live: .green
        case .lost, .error: .red
        }
    }

    /// A softer wash for the circle behind the glyph.
    var fill: Color {
        switch self {
        case .off, .waiting: .white.opacity(0.08)
        case .searching: .orange.opacity(0.18)
        case .live: .green.opacity(0.22)
        case .lost, .error: .red.opacity(0.16)
        }
    }
}
