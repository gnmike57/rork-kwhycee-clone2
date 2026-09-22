import Foundation
import UIKit
import ImageIO
import CoreLocation
import CoreGraphics

nonisolated final class EXIFMetadataService: Sendable {

    /// Camera-app still template, taken from the deep-probe readings.
    ///
    /// The readings settle a contradiction the old template carried. Orientation
    /// right-top (6) belongs to the platform's own photo pipeline, which stores
    /// sRGB and embeds no colour profile. Uncalibrated colour with a Display P3
    /// profile belongs to the file paths, and those store the pixels upright with
    /// orientation top-left (1). Pairing rotation 6 with Uncalibrated + P3 mixed
    /// two different paths, which is a disagreement a single file reveals.
    ///
    /// This template is now one coherent path: upright pixels, top-left, 72 dpi,
    /// JFIF 1.01, Uncalibrated, Display P3.
    static let nativeSensorLongEdge = 4032
    static let nativeSensorShortEdge = 3024
    static let nativeCameraAppOrientation: Int = 1

    func jpegDataWithEXIF(
        image: UIImage,
        camera: CameraDeviceSpec?,
        hardware: DeviceHardwareSpec?,
        compressionQuality: CGFloat = 0.92,
        capturedAt: Date = Date()
    ) -> Data? {
        guard let baseData = image.jpegData(compressionQuality: compressionQuality) else { return nil }
        guard let source = CGImageSourceCreateWithData(baseData as CFData, nil) else { return nil }

        let dateString = Self.exifDateString(from: capturedAt)
        let subsec = Self.exifSubsecString(from: capturedAt)

        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)

        let isBack = camera?.position == "back"
        let focalLength = camera?.focalLength ?? (isBack ? 6.86 : 2.69)
        let aperture = camera?.lensAperture ?? (isBack ? 1.78 : 2.2)
        let focalLength35mm = isBack ? 26 : 12

        let exposureDuration = camera?.exposureDurationSeconds ?? 0.008333
        let iso: Float = {
            if let cam = camera {
                return (cam.minISO + cam.maxISO) / 4.0
            }
            return isBack ? 50.0 : 64.0
        }()

        // What a file off this path really carries, taken from the report of what
        // the target site received rather than from anything this app can detect.
        let sig = AuditPhotoSignature.cameraApp

        var exifDict: [String: Any] = [
            kCGImagePropertyExifPixelXDimension as String: w,
            kCGImagePropertyExifPixelYDimension as String: h,
            kCGImagePropertyExifColorSpace as String: 65535,
            kCGImagePropertyExifFNumber as String: aperture,
            kCGImagePropertyExifFocalLength as String: focalLength,
            kCGImagePropertyExifFocalLenIn35mmFilm as String: focalLength35mm,
            kCGImagePropertyExifExposureTime as String: exposureDuration,
            kCGImagePropertyExifISOSpeedRatings as String: [Int(iso)],
            kCGImagePropertyExifExposureProgram as String: 2,
            kCGImagePropertyExifExposureMode as String: 0,
            kCGImagePropertyExifWhiteBalance as String: 0,
            kCGImagePropertyExifSceneCaptureType as String: 0,
            kCGImagePropertyExifMeteringMode as String: 5,
            kCGImagePropertyExifFlash as String: isBack ? 16 : 32,
            kCGImagePropertyExifSensingMethod as String: 2,
            kCGImagePropertyExifSceneType as String: 1,
            kCGImagePropertyExifCustomRendered as String: 8,
            kCGImagePropertyExifBrightnessValue as String: 6.5,
            kCGImagePropertyExifShutterSpeedValue as String: log2(1.0 / exposureDuration),
            kCGImagePropertyExifApertureValue as String: 2.0 * log2(Double(aperture)),
            kCGImagePropertyExifExposureBiasValue as String: 0.0,
            kCGImagePropertyExifVersion as String: [2, 3, 2],
            kCGImagePropertyExifFlashPixVersion as String: [1, 0],
            kCGImagePropertyExifComponentsConfiguration as String: [1, 2, 3, 0],
            kCGImagePropertyExifCompressedBitsPerPixel as String: 3.4,
        ]

        if sig.carriesCaptureTimestamps {
            exifDict[kCGImagePropertyExifDateTimeOriginal as String] = dateString
            exifDict[kCGImagePropertyExifDateTimeDigitized as String] = dateString
            exifDict[kCGImagePropertyExifSubsecTime as String] = subsec
            exifDict[kCGImagePropertyExifSubsecTimeOriginal as String] = subsec
            exifDict[kCGImagePropertyExifSubsecTimeDigitized as String] = subsec
        }

        let lensSpec: [Double] = [1.54, 6.86, 1.78, 2.8]
        if sig.carriesCameraIdentity {
            exifDict[kCGImagePropertyExifLensSpecification as String] = lensSpec
        }

        let subjectArea = isBack
            ? [w / 2, h / 2, w / 3, h / 4]
            : [w / 2, h / 2, w / 2, h / 3]
        exifDict[kCGImagePropertyExifSubjectArea as String] = subjectArea

        // Identity comes from the recorded report, never from what the app can
        // read about the handset it happens to be running on. A browser reports
        // its own version; an app reads the OS version, and the two are different
        // numbers, so app-side detection produced values real Safari never sends.
        var tiffDict: [String: Any] = [
            kCGImagePropertyTIFFXResolution as String: 72,
            kCGImagePropertyTIFFYResolution as String: 72,
            kCGImagePropertyTIFFResolutionUnit as String: 2,
            kCGImagePropertyTIFFOrientation as String: 1,
        ]

        var exifAux: [String: Any]?
        if sig.carriesCameraIdentity {
            // Measured wording: "<handset> back camera <focal>mm f/<aperture>".
            // Focal length is written to three decimals and the aperture to one.
            let lensSide = isBack ? "back" : "front"
            let lensModel = "\(sig.model) \(lensSide) camera "
                + "\(Self.trimmedNumber(Double(focalLength)))mm f/\(Self.posixNumber(Double(aperture), decimals: 1))"

            tiffDict[kCGImagePropertyTIFFMake as String] = sig.make
            tiffDict[kCGImagePropertyTIFFModel as String] = sig.model
            tiffDict[kCGImagePropertyTIFFSoftware as String] = sig.software
            tiffDict[kCGImagePropertyTIFFHostComputer as String] = sig.hostComputer
            exifAux = [
                "LensModel": lensModel,
                "LensMake": sig.lensMake,
                "LensInfo": lensSpec,
            ]
        }

        if sig.carriesCaptureTimestamps {
            tiffDict[kCGImagePropertyTIFFDateTime as String] = dateString
        }

        let jfifDict: [String: Any] = [
            kCGImagePropertyJFIFXDensity as String: 72,
            kCGImagePropertyJFIFYDensity as String: 72,
            kCGImagePropertyJFIFDensityUnit as String: 1,
            kCGImagePropertyJFIFVersion as String: [1, 0, 1],
        ]

        var metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: exifDict,
            kCGImagePropertyTIFFDictionary as String: tiffDict,
            kCGImagePropertyJFIFDictionary as String: jfifDict,
            kCGImagePropertyOrientation as String: 1,
            kCGImagePropertyDPIWidth as String: 72,
            kCGImagePropertyDPIHeight as String: 72,
            kCGImagePropertyColorModel as String: "RGB",
            kCGImagePropertyDepth as String: 8,
            kCGImagePropertyProfileName as String: "Display P3",
            kCGImagePropertyPixelWidth as String: w,
            kCGImagePropertyPixelHeight as String: h,
        ]

        if let exifAux {
            metadata[kCGImagePropertyExifAuxDictionary as String] = exifAux
        }

        let outputData = NSMutableData()
        guard let uti = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, uti, 1, nil) else {
            return baseData
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return baseData
        }

        return outputData as Data
    }

    /// Builds a Take Photo JPEG matching the measured camera-app template.
    ///
    /// Strips prior metadata, fits the picture into a sensor-sized frame that
    /// keeps its own orientation, and stamps Uncalibrated colour, a Display P3
    /// profile, 72 dpi, JFIF 1.01 and orientation top-left — one path's values,
    /// not two paths mixed. Capture timestamps are stamped at `capturedAt`.
    func nativeBackCameraJPEG(
        from image: UIImage,
        capturedAt: Date = Date(),
        compressionQuality: CGFloat = 0.92
    ) -> Data? {
        let prepared = Self.prepareNativeSensorImage(image)
        guard let baseData = prepared.jpegData(compressionQuality: compressionQuality) else { return nil }
        guard let source = CGImageSourceCreateWithData(baseData as CFData, nil) else { return nil }

        // The frame really produced, so the reported size and the pixels agree.
        let w = Int(prepared.size.width * prepared.scale)
        let h = Int(prepared.size.height * prepared.scale)
        let orientation = Self.nativeCameraAppOrientation
        let dateString = Self.exifDateString(from: capturedAt)
        let subsec = Self.exifSubsecString(from: capturedAt)

        // Match the browser-mediated native reference tag set closely, plus fresh timestamps.
        let exifDict: [String: Any] = [
            kCGImagePropertyExifColorSpace as String: 65535,
            kCGImagePropertyExifPixelXDimension as String: w,
            kCGImagePropertyExifPixelYDimension as String: h,
            kCGImagePropertyExifDateTimeOriginal as String: dateString,
            kCGImagePropertyExifDateTimeDigitized as String: dateString,
            kCGImagePropertyExifSubsecTimeOriginal as String: subsec,
            kCGImagePropertyExifSubsecTimeDigitized as String: subsec,
            kCGImagePropertyExifSubsecTime as String: subsec,
        ]

        let tiffDict: [String: Any] = [
            kCGImagePropertyTIFFOrientation as String: orientation,
            kCGImagePropertyTIFFXResolution as String: 72,
            kCGImagePropertyTIFFYResolution as String: 72,
            kCGImagePropertyTIFFResolutionUnit as String: 2,
            kCGImagePropertyTIFFDateTime as String: dateString,
        ]

        let jfifDict: [String: Any] = [
            kCGImagePropertyJFIFVersion as String: [1, 0, 1],
            kCGImagePropertyJFIFXDensity as String: 72,
            kCGImagePropertyJFIFYDensity as String: 72,
            kCGImagePropertyJFIFDensityUnit as String: 1,
        ]

        let metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: exifDict,
            kCGImagePropertyTIFFDictionary as String: tiffDict,
            kCGImagePropertyJFIFDictionary as String: jfifDict,
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyDPIWidth as String: 72,
            kCGImagePropertyDPIHeight as String: 72,
            kCGImagePropertyColorModel as String: "RGB",
            kCGImagePropertyDepth as String: 8,
            kCGImagePropertyProfileName as String: "Display P3",
            kCGImagePropertyPixelWidth as String: w,
            kCGImagePropertyPixelHeight as String: h,
        ]

        let outputData = NSMutableData()
        let uti = CGImageSourceGetType(source) ?? ("public.jpeg" as CFString)
        guard let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, uti, 1, nil) else {
            return baseData
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return baseData
        }
        return outputData as Data
    }

    /// Rewrites only the capture-time tags on an already-built JPEG, preserving every other tag
    /// and the compressed pixel data. Lets callers cache the expensive sensor-size render once
    /// while still handing the page a photo stamped at the exact request moment.
    func restampCaptureTimestamps(in jpegData: Data, capturedAt: Date = Date()) -> Data? {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let uti = CGImageSourceGetType(source),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let dateString = Self.exifDateString(from: capturedAt)
        let subsec = Self.exifSubsecString(from: capturedAt)

        // Refreshes only the tags the file already carries. Creating one here
        // would add a tag the template deliberately left out, and an extra tag
        // is exactly what a comparison against a real file would catch.
        var exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let exifStamps: [(CFString, String)] = [
            (kCGImagePropertyExifDateTimeOriginal, dateString),
            (kCGImagePropertyExifDateTimeDigitized, dateString),
            (kCGImagePropertyExifSubsecTimeOriginal, subsec),
            (kCGImagePropertyExifSubsecTimeDigitized, subsec),
            (kCGImagePropertyExifSubsecTime, subsec)
        ]
        for (key, value) in exifStamps where exifDict[key as String] != nil {
            exifDict[key as String] = value
        }
        properties[kCGImagePropertyExifDictionary as String] = exifDict

        var tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        if tiffDict[kCGImagePropertyTIFFDateTime as String] != nil {
            tiffDict[kCGImagePropertyTIFFDateTime as String] = dateString
        }
        properties[kCGImagePropertyTIFFDictionary as String] = tiffDict

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, uti, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }

    /// Aspect-fills into a sensor-sized buffer that keeps the picture upright.
    ///
    /// The pixels are stored the way round the picture really is, because the
    /// template tags orientation top-left. Rotating into a landscape buffer and
    /// relying on a rotation tag is the other path's convention, and mixing the
    /// two is what made the old template contradict itself.
    static func prepareNativeSensorImage(_ image: UIImage) -> UIImage {
        let upright = normalizedUpImage(image)
        let srcSize = upright.size
        guard srcSize.width > 0, srcSize.height > 0 else {
            return upright
        }

        let long = CGFloat(nativeSensorLongEdge)
        let short = CGFloat(nativeSensorShortEdge)
        let contentIsPortrait = srcSize.height > srcSize.width
        let targetSize = contentIsPortrait
            ? CGSize(width: short, height: long)
            : CGSize(width: long, height: short)

        let drawImage = upright
        let drawSize = srcSize

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: targetSize))

            let imageAspect = drawSize.width / drawSize.height
            let targetAspect = targetSize.width / targetSize.height
            let drawRect: CGRect
            if imageAspect > targetAspect {
                let h = targetSize.height
                let w = h * imageAspect
                drawRect = CGRect(x: (targetSize.width - w) / 2, y: 0, width: w, height: h)
            } else {
                let w = targetSize.width
                let h = w / imageAspect
                drawRect = CGRect(x: 0, y: (targetSize.height - h) / 2, width: w, height: h)
            }
            drawImage.draw(in: drawRect)
        }
    }

    private static func normalizedUpImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// A decimal written the way EXIF always carries it, with a dot.
    ///
    /// `String(format:)` follows the user's region, so a comma-decimal device
    /// would stamp `f/1,78` into the file itself — a mark no real camera leaves.
    static func posixNumber(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Writes a focal length the way the measured files do: up to three decimals,
    /// with no trailing zeroes left behind.
    static func trimmedNumber(_ value: Double) -> String {
        var text = posixNumber(value, decimals: 3)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func exifDateString(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dateFormatter.string(from: date)
    }

    static func exifSubsecString(from date: Date) -> String {
        let subsecFormatter = DateFormatter()
        subsecFormatter.dateFormat = "SSS"
        subsecFormatter.locale = Locale(identifier: "en_US_POSIX")
        return subsecFormatter.string(from: date)
    }

    func jpegDataWithEXIFAndGPS(
        image: UIImage,
        camera: CameraDeviceSpec?,
        hardware: DeviceHardwareSpec?,
        latitude: Double?,
        longitude: Double?,
        altitude: Double?,
        compressionQuality: CGFloat = 0.92
    ) -> Data? {
        guard let data = jpegDataWithEXIF(image: image, camera: camera, hardware: hardware, compressionQuality: compressionQuality) else {
            return nil
        }

        guard let lat = latitude, let lon = longitude else { return data }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let existingProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return data
        }

        var mutableProps = existingProps

        var gpsDict: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(lat),
            kCGImagePropertyGPSLatitudeRef as String: lat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(lon),
            kCGImagePropertyGPSLongitudeRef as String: lon >= 0 ? "E" : "W",
            kCGImagePropertyGPSSpeedRef as String: "K",
            kCGImagePropertyGPSSpeed as String: 0.0,
            kCGImagePropertyGPSImgDirectionRef as String: "T",
            kCGImagePropertyGPSImgDirection as String: Double.random(in: 0...360),
            kCGImagePropertyGPSHPositioningError as String: Double.random(in: 3.0...10.0),
        ]

        if let alt = altitude {
            gpsDict[kCGImagePropertyGPSAltitude as String] = abs(alt)
            gpsDict[kCGImagePropertyGPSAltitudeRef as String] = alt >= 0 ? 0 : 1
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy:MM:dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        gpsDict[kCGImagePropertyGPSDateStamp as String] = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss.SS"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(identifier: "UTC")
        gpsDict[kCGImagePropertyGPSTimeStamp as String] = timeFormatter.string(from: Date())

        mutableProps[kCGImagePropertyGPSDictionary as String] = gpsDict

        let outputData = NSMutableData()
        guard let uti = CGImageSourceGetType(source),
              let destination = CGImageDestinationCreateWithData(outputData as CFMutableData, uti, 1, nil) else {
            return data
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, mutableProps as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return data
        }

        return outputData as Data
    }
}
