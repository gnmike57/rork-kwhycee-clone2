import UIKit

/// Small, consistent feedback for the floating media controls.
///
/// Generators are kept alive and prepared ahead of a tap, so the first press
/// after a screen appears isn't silent.
@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Warms the generators up. Call when a control surface appears.
    static func prepare() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        notificationGenerator.prepare()
    }

    static func tick() {
        lightGenerator.impactOccurred()
    }

    static func firm() {
        mediumGenerator.impactOccurred()
    }

    static func snap() {
        rigidGenerator.impactOccurred(intensity: 0.7)
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
}
