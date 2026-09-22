import Foundation

/// Where face readings come from.
nonisolated enum FaceTrackingMode: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Apple's face tracking through this phone's front camera.
    case thisPhone

    /// Live Link Face on a second iPhone, streaming to this phone over the local network.
    case secondPhone

    nonisolated var id: String { rawValue }

    var title: String {
        switch self {
        case .thisPhone: "This iPhone"
        case .secondPhone: "Second iPhone"
        }
    }
}
