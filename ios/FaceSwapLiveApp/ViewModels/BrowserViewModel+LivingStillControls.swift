import UIKit

extension BrowserViewModel {
    /// The still the living-still draw would use right now: the page's feed
    /// first, then the active stream, then an open Frame Check. The Face
    /// Tracking sheet's photo controls act on whatever this answers.
    var activeLivingStill: (image: UIImage, facing: CameraFacing, slot: Int)? {
        if let feed = livingFeed,
           isStill(facing: feed.facing, slot: feed.slot),
           let image = previewImage(facing: feed.facing, slot: feed.slot) {
            return (image, feed.facing, feed.slot)
        }
        if isLiveStreamActive, let facing = activeStreamFacing {
            let slot = facing == .back ? backQueueIndex : frontQueueIndex
            if isStill(facing: facing, slot: slot),
               let image = previewImage(facing: facing, slot: slot) {
                return (image, facing, slot)
            }
        }
        if let request = frameCheckRequest,
           isStill(facing: request.facing, slot: request.slot),
           let image = previewImage(facing: request.facing, slot: request.slot) {
            return (image, request.facing, request.slot)
        }
        return nil
    }

    /// True when the active photo has a face rig, so the sheet's photo
    /// controls have something to steer.
    var activeStillHasFace: Bool {
        guard let still = activeLivingStill else { return false }
        return frameCache.rig(for: still.image) != nil
    }

    // MARK: - Strength

    /// The strength stored for a photo, or the shipped default.
    func livingStrength(for image: UIImage) -> Double {
        guard let fingerprint = PhotoFingerprint.make(from: image) else {
            return PhotoMemory.defaultStrength
        }
        return photoMemory.match(fingerprint)?.strength ?? PhotoMemory.defaultStrength
    }

    /// Writes strength for a photo, keeping every other memory field. No-op
    /// when nothing changed, so a slider resting at its stored value never
    /// churns the store.
    func setLivingStrength(_ value: Double, for image: UIImage) {
        let clamped = min(max(value, 0), 1)
        guard let fingerprint = PhotoFingerprint.make(from: image) else { return }
        if let existing = photoMemory.match(fingerprint) {
            guard existing.strength != clamped else { return }
            photoMemory.save(PhotoMemory(
                fingerprint: existing.fingerprint,
                strength: clamped,
                calibration: existing.calibration,
                rig: existing.rig,
                savedAt: existing.savedAt
            ))
        } else if let rig = frameCache.rig(for: image) {
            photoMemory.save(PhotoMemory(
                fingerprint: fingerprint,
                strength: clamped,
                calibration: nil,
                rig: rig,
                savedAt: Date()
            ))
        }
    }

    // MARK: - Per-photo calibration

    /// The rest pose remembered for a photo, if one is.
    func livingCalibration(for image: UIImage) -> FacePose? {
        guard let fingerprint = PhotoFingerprint.make(from: image) else { return nil }
        return FacePose.decodeCalibration(photoMemory.match(fingerprint)?.calibration)
    }

    /// Saves or clears the rest pose for a photo.
    func setLivingCalibration(_ baseline: FacePose?, for image: UIImage) {
        let stored = baseline?.encodeCalibration()
        guard let fingerprint = PhotoFingerprint.make(from: image) else { return }
        if let existing = photoMemory.match(fingerprint) {
            guard existing.calibration != stored else { return }
            photoMemory.save(PhotoMemory(
                fingerprint: existing.fingerprint,
                strength: existing.strength,
                calibration: stored,
                rig: existing.rig,
                savedAt: existing.savedAt
            ))
        } else if stored != nil, let rig = frameCache.rig(for: image) {
            photoMemory.save(PhotoMemory(
                fingerprint: fingerprint,
                strength: PhotoMemory.defaultStrength,
                calibration: stored,
                rig: rig,
                savedAt: Date()
            ))
        }
    }
}
