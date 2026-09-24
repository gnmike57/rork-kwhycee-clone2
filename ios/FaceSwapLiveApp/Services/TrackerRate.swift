import Foundation

/// Front-camera tracking rate. The page draw stays at 30; only the tracker
/// steps down when the phone is hot.
nonisolated enum TrackerRate {
    static func framesPerSecond(for thermal: ProcessInfo.ThermalState) -> Int {
        switch thermal {
        case .serious, .critical: 30
        default: 60
        }
    }

    /// Index of the format closest to `fps`. A tie keeps the earlier entry,
    /// which is the higher-quality format in Apple's list.
    static func indexPreferring(_ fps: Int, among rates: [Int]) -> Int? {
        guard !rates.isEmpty else { return nil }
        var best = 0
        var bestDistance = abs(rates[0] - fps)
        for index in rates.indices.dropFirst() {
            let distance = abs(rates[index] - fps)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}
