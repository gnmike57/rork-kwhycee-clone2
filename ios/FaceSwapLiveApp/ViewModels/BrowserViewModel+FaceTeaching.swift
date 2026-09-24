import UIKit

extension BrowserViewModel {
    func restoreKeptStills() {
        for slot in keptStills.restored() {
            guard let facing = CameraFacing(rawValue: slot.facing) else { continue }
            placeRestored(slot.image, facing: facing, slot: slot.slot, crops: slot.crops, stamp: slot.stamp, original: slot.original)
        }
    }

    func rememberKeptSlot(facing: CameraFacing, slot: Int) {
        guard isStill(facing: facing, slot: slot), let image = previewImage(facing: facing, slot: slot) else {
            keptStills.remove(facing: facing.rawValue, slot: slot)
            return
        }
        let stamp = facing == .front && slot == 0 ? imageSchemeHandler.frontImageData : nil
        keptStills.save(
            facing: facing.rawValue,
            slot: slot,
            image: image,
            stamp: stamp,
            original: frameCache.original(for: image),
            crops: shapeCrops(facing: facing, slot: slot)
        )
    }

    func dropKeptSlot(facing: CameraFacing, slot: Int) {
        keptStills.remove(facing: facing.rawValue, slot: slot)
    }

    func ensureFaceMap(for image: UIImage) {
        guard LivingStills.isAvailable, !frameCache.hasSearchedMap(for: image) else { return }
        frameCache.markMapSearching(image)
        Task { @MainActor [weak self] in
            let result = await FaceMapper.map(image)
            guard let self else { return }
            var rig = result.rig
            if let fingerprint = result.fingerprint, let stored = self.photoMemory.match(fingerprint) {
                rig = stored.rig.version == FaceRig.currentVersion
                    ? stored.rig
                    : stored.rig.rebuilt(version: FaceRig.currentVersion)
            } else if let rig, let fingerprint = result.fingerprint {
                self.photoMemory.save(PhotoMemory(
                    fingerprint: fingerprint,
                    strength: PhotoMemory.defaultStrength,
                    calibration: nil,
                    rig: rig,
                    savedAt: Date()
                ))
            }
            self.frameCache.setMap(rig, note: result.note, faces: result.faces, for: image)
        }
    }

    func saveFaceRig(_ rig: FaceRig, for image: UIImage) {
        frameCache.setMap(rig, note: nil, faces: frameCache.mappedFaces(for: image), for: image)
        guard let fingerprint = PhotoFingerprint.make(from: image) else { return }
        let existing = photoMemory.match(fingerprint)
        photoMemory.save(PhotoMemory(
            fingerprint: fingerprint,
            strength: existing?.strength ?? PhotoMemory.defaultStrength,
            calibration: existing?.calibration,
            rig: rig,
            savedAt: Date()
        ))
    }

    func copyFaceCorrections(_ rig: FaceRig, from facing: CameraFacing, slot: Int) {
        let other: CameraFacing = facing == .front ? .back : .front
        guard let image = previewImage(facing: other, slot: slot) else { return }
        var paired = frameCache.rig(for: image)
        if paired == nil, let fingerprint = PhotoFingerprint.make(from: image) {
            paired = photoMemory.match(fingerprint)?.rig
        }
        guard var paired else { return }
        paired.nudges = rig.nudges
        saveFaceRig(paired, for: image)
    }

    func canCopyFaceCorrections(from facing: CameraFacing, slot: Int) -> Bool {
        let other: CameraFacing = facing == .front ? .back : .front
        return isStill(facing: other, slot: slot)
    }

    private func placeRestored(_ image: UIImage, facing: CameraFacing, slot: Int, crops: ShapeCrops, stamp: Data?, original: UIImage?) {
        switch (facing, slot) {
        case (.front, 0):
            frontImage = image
            frontVideoURL = nil
            frontSourceType = .image
            frontCrop = crops
            imageSchemeHandler.setFrontSourceImage(image, slot: 0)
            if let stamp { imageSchemeHandler.frontImageData = stamp }
        case (.front, _):
            frontImage2 = image
            frontVideoURL2 = nil
            frontSourceType2 = .image
            frontCrop2 = crops
            imageSchemeHandler.setFrontSourceImage(image, slot: 1)
        case (.back, 0):
            backImage = image
            backVideoURL = nil
            backSourceType = .image
            backCrop = crops
            imageSchemeHandler.setBackSourceImage(image, slot: 0)
            imageSchemeHandler.stampBackOnDemand = true
        case (.back, _):
            backImage2 = image
            backVideoURL2 = nil
            backSourceType2 = .image
            backCrop2 = crops
            imageSchemeHandler.setBackSourceImage(image, slot: 1)
        }
        if let original {
            frameCache.setOriginal(original, for: image)
        }
    }
}

extension FrameCheckCache {
    func rig(for image: UIImage) -> FaceRig? {
        lookup(image)?.rig
    }

    func mapNote(for image: UIImage) -> String? {
        lookup(image)?.mapNote
    }

    func hasSearchedMap(for image: UIImage) -> Bool {
        lookup(image)?.mapSearched ?? false
    }

    func mappedFaces(for image: UIImage) -> [MappedFace] {
        lookup(image)?.mappedFaces ?? []
    }

    func markMapSearching(_ image: UIImage) {
        let item = entry(for: image)
        item.mapSearching = true
        touch()
    }

    func setMap(_ rig: FaceRig?, note: String?, faces: [MappedFace], for image: UIImage) {
        let item = entry(for: image)
        item.rig = rig
        item.mapNote = note
        item.mappedFaces = faces
        item.mapSearched = true
        item.mapSearching = false
        touch()
    }
}
