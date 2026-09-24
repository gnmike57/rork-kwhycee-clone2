import Foundation

/// Living stills stay off in App Store builds until the iPhone 17 pass is done.
/// Debug builds keep the engine available so it can be exercised.
nonisolated enum LivingStills {
    static var isAvailable: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
