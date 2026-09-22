import Photos
import UIKit

/// Writes prepared media into the user's photo library so the real iOS picker can
/// hand it to a web page. Used by Native Picker Mode, where nothing is injected.
nonisolated final class PhotoLibraryService: Sendable {
    nonisolated enum SaveError: LocalizedError {
        case permissionDenied
        case permissionRestricted
        case saveFailed

        nonisolated var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Photo access is off. Enable Add Photos Only in Settings to save media."
            case .permissionRestricted:
                "Saving to Photos is restricted on this device."
            case .saveFailed:
                "Could not save to Photos. Please try again."
            }
        }
    }

    /// Requests add-only access, which never exposes the existing library to the app.
    private func ensureAddAuthorization() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited:
            return
        case .restricted:
            throw SaveError.permissionRestricted
        case .denied:
            throw SaveError.permissionDenied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            switch granted {
            case .authorized, .limited: return
            case .restricted: throw SaveError.permissionRestricted
            default: throw SaveError.permissionDenied
            }
        @unknown default:
            throw SaveError.permissionDenied
        }
    }

    /// Saves JPEG bytes verbatim so the embedded capture metadata survives.
    func saveJPEG(_ data: Data) async throws {
        try await ensureAddAuthorization()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = Self.photoFilename()
                request.addResource(with: .photo, data: data, options: options)
            }
        } catch {
            throw SaveError.saveFailed
        }
    }

    func saveVideo(at url: URL) async throws {
        try await ensureAddAuthorization()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SaveError.saveFailed
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw SaveError.saveFailed
        }
    }

    /// Matches the naming the camera roll uses, so the picker entry looks ordinary.
    private static func photoFilename() -> String {
        let sequence = Int.random(in: 1000...9999)
        return "IMG_\(sequence).JPG"
    }
}
