import SwiftUI

/// Root of the Live Link tab.
struct LiveLinkTabView: View {
    var body: some View {
        NavigationStack {
            LiveLinkConnectionView()
        }
        .preferredColorScheme(.dark)
    }
}

extension FaceTrackingController {
    /// The Live Link tab's icon, which doubles as its status: a dot while
    /// streaming, plain waves while listening or searching, struck out when off.
    var tabSymbol: String {
        switch state {
        case .receiving, .live: "dot.radiowaves.left.and.right"
        case .off, .standby, .unavailable: "antenna.radiowaves.left.and.right.slash"
        case .starting, .listening, .searching, .lost: "antenna.radiowaves.left.and.right"
        }
    }
}
