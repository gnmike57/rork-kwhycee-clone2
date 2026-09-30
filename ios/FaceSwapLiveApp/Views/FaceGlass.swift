import SwiftUI

extension View {
    /// Liquid Glass on iOS 26 and 27, materials on iOS 18 — the Face Tracking
    /// surfaces follow the plan's split.
    @ViewBuilder
    func faceGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
