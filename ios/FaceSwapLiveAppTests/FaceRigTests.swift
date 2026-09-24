import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import FaceSwapLiveApp

/// Stage 2: the face rig, photo memory and kept stills.
@MainActor
struct FaceRigTests {
    @Test func syntheticFaceBuildsEighteenHandlesInOrder() {
        let face = Self.frontFace(roll: 0, yaw: 0)
        let rig = try! #require(FaceRigBuilder.build(from: face, wearsGlasses: false, teethVisible: false))
        #expect(rig.handleIndex.count == FaceHandle.allCases.count)
        #expect(rig.triangles.count > 20)
        #expect(Set(rig.triangles.map(\.layer)).isSuperset(of: [.eye, .mouth, .jaw, .edge]))

        let leftEye = try! #require(rig.position(of: .leftEyeCenter))
        let rightEye = try! #require(rig.position(of: .rightEyeCenter))
        let nose = try! #require(rig.position(of: .noseTip))
        let lips = try! #require(rig.position(of: .upperLip))
        let chin = try! #require(rig.position(of: .chin))
        #expect(leftEye.x > rightEye.x)
        #expect(leftEye.y < nose.y)
        #expect(rightEye.y < nose.y)
        #expect(nose.y < lips.y)
        #expect(lips.y < chin.y)
        #expect(nose.x > rightEye.x && nose.x < leftEye.x)

        let brow = try! #require(rig.position(of: .leftBrowCenter))
        #expect(rig.vertices.contains { $0.y < brow.y - 0.01 })
        #expect(rig.vertices.contains { $0.y > chin.y + 0.01 })
        #expect(FaceRigBuilder.edgeReach(temple: true) < FaceRigBuilder.edgeReach(temple: false))
    }

    @Test func nudgesSurviveAVersionBumpAndFallOff() {
        var rig = try! #require(FaceRigBuilder.build(from: Self.frontFace(roll: 0, yaw: 0), wearsGlasses: false, teethVisible: false))
        rig.nudges[.mouthLeft] = FaceNudge(dx: 0.04, dy: 0.01)
        let rebuilt = rig.rebuilt(version: 2)
        #expect(rebuilt.version == 2)
        #expect(rebuilt.nudges[.mouthLeft] == FaceNudge(dx: 0.04, dy: 0.01))

        let moved = rig.deformedVertices()
        let mouth = rig.handleIndex[.mouthLeft]!
        let eye = rig.handleIndex[.leftEyeCenter]!
        #expect(abs(moved[mouth].x - rig.vertices[mouth].x - 0.04) < 0.01)
        #expect(abs(moved[eye].x - rig.vertices[eye].x) < 0.01)
    }

    @Test func largestUprightFaceWins() {
        let sideways = Self.frontFace(roll: 80 * .pi / 180, yaw: 0, id: 1, scale: 0.5)
        let upright = Self.frontFace(roll: 0.2, yaw: 0, id: 2, scale: 0.2)
        #expect(FacePicker.largestUpright(among: [sideways, upright])?.id == 2)
        #expect(FacePicker.largestUpright(among: [sideways])?.id == 1)
    }

    @Test func headTurnGainDropsPastFifteenDegrees() {
        #expect(FaceRig.headTurnGain(turnRadians: 0) == 1)
        #expect(FaceRig.headTurnGain(turnRadians: 10 * .pi / 180) == 1)
        #expect(FaceRig.headTurnGain(turnRadians: 30 * .pi / 180) < 1)
    }

    @Test func glassesAndTeethFlagsReadThePixels() {
        let width = 40
        let height = 30
        var plain = [UInt8](repeating: 180, count: width * height)
        let band = CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.2)
        #expect(!FaceFlags.wearsGlasses(luma: plain, width: width, height: height, eyeBand: band))
        for y in 10..<14 {
            for x in 4..<36 { plain[y * width + x] = 20 }
        }
        #expect(FaceFlags.wearsGlasses(luma: plain, width: width, height: height, eyeBand: band))

        let mouth = CGRect(x: 0.3, y: 0.6, width: 0.4, height: 0.2)
        var dark = [UInt8](repeating: 30, count: width * height)
        #expect(!FaceFlags.teethVisible(luma: dark, width: width, height: height, mouth: mouth, opening: 0.05, faceHeight: 0.5))
        for y in 18..<24 {
            for x in 12..<28 { dark[y * width + x] = 220 }
        }
        #expect(FaceFlags.teethVisible(luma: dark, width: width, height: height, mouth: mouth, opening: 0.05, faceHeight: 0.5))
        #expect(!FaceFlags.teethVisible(luma: dark, width: width, height: height, mouth: mouth, opening: 0.01, faceHeight: 0.5))
    }

    @Test func exactAndReencodedPicturesMatchButCropsDoNot() throws {
        let image = Self.pattern(size: CGSize(width: 96, height: 128))
        let original = try #require(PhotoFingerprint.make(from: image))
        #expect(original.matches(original))

        let jpeg = try #require(Self.encoded(image, type: UTType.jpeg, quality: 0.45))
        let decoded = try #require(Self.image(from: jpeg))
        let again = try #require(PhotoFingerprint.make(from: decoded))
        #expect(original.matches(again))

        let heic = try #require(Self.encoded(image, type: UTType.heic, quality: 0.5))
        let heicImage = try #require(Self.image(from: heic))
        #expect(original.matches(try #require(PhotoFingerprint.make(from: heicImage))))
        #expect(again.matches(try #require(PhotoFingerprint.make(from: heicImage))))

        let crop = Self.pattern(size: CGSize(width: 96, height: 128), cropped: true)
        #expect(!original.matches(try #require(PhotoFingerprint.make(from: crop))))
    }

    @Test func memoryRoundTripsAndDropsTheOldest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PhotoMemoryStore(directory: directory, photoBudget: 2, byteBudget: 50_000_000)
        let older = Self.memory(id: 1, savedAt: Date(timeIntervalSince1970: 10))
        let middle = Self.memory(id: 2, savedAt: Date(timeIntervalSince1970: 20))
        let newer = Self.memory(id: 3, savedAt: Date(timeIntervalSince1970: 30))
        store.save(older)
        store.save(middle)
        store.save(newer)
        #expect(store.count == 2)
        #expect(store.match(older.fingerprint) == nil)
        #expect(store.match(newer.fingerprint)?.strength == PhotoMemory.defaultStrength)

        let tight = PhotoMemoryStore(directory: directory.appendingPathComponent("tight"), photoBudget: 20, byteBudget: 1)
        tight.save(older)
        tight.save(newer)
        #expect(tight.count == 1)
        #expect(tight.match(newer.fingerprint) != nil)

        let data = try Data(contentsOf: directory.appendingPathComponent("memories.json"))
        let decoded = try JSONDecoder().decode([PhotoMemory].self, from: data)
        #expect(decoded.count == 2)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func keptStillsRestoreSwapPromoteAndSkipMissingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = KeptStillStore(directory: directory)
        let red = Self.solid(.red)
        let blue = Self.solid(.blue)
        store.save(facing: "front", slot: 1, image: blue, stamp: Data([1, 2, 3]), original: nil, crops: .identity)
        let promoted = store.restored()
        #expect(promoted.count == 1)
        #expect(promoted[0].slot == 0)
        #expect(promoted[0].stamp == Data([1, 2, 3]))

        store.save(facing: "front", slot: 0, image: red, stamp: nil, original: nil, crops: .identity)
        store.save(facing: "front", slot: 1, image: blue, stamp: nil, original: nil, crops: .identity)
        store.swap(facing: "front")
        let swapped = store.restored().sorted { $0.slot < $1.slot }
        #expect(swapped.map(\.slot) == [0, 1])
        #expect(Self.isBlue(swapped[0].image))
        #expect(Self.isRed(swapped[1].image))

        store.remove(facing: "front", slot: 0)
        let afterClear = store.restored()
        #expect(afterClear.count == 1)
        #expect(afterClear[0].slot == 0)
        #expect(Self.isRed(afterClear[0].image))

        store.clearAll()
        #expect(store.restored().isEmpty)
        let leftover = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(leftover.filter { $0.pathExtension == "png" || $0.pathExtension == "json" }.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func protectedStorageIsLockedAndLeftOutOfBackups() throws {
        let directory = try ProtectedDirectory.make(
            named: "FaceMemoryTest",
            base: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
        #expect(ProtectedDirectory.isProtected(directory))
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    @Test func pageNamesDoNotMentionFacePoints() {
        let script = StyleSheetProvider.patchScript
        #expect(!script.contains("Face points"))
        #expect(!script.contains(FaceMapNote.couldntMap))
        #expect(!script.contains("jawOpen"))
    }

    @Test func portraitsMapInOrderWithTheRightFlags() async throws {
        let straight = try Self.portrait("portrait_neutral_headshot")
        let tilted = try Self.portrait("photorealistic_head_and")
        let glasses = try Self.portrait("portrait_dark_glasses")
        let turned = try Self.portrait("portrait_head_shoulders_2")
        let teeth = try Self.portrait("portrait_teeth_smile")
        let smile = try Self.portrait("portrait_head_shoulders")

        let straightRig = try await Self.mapped(straight)
        Self.expectOrder(straightRig)
        #expect(abs(straightRig.rest.tilt) < 10 * .pi / 180)
        #expect(!straightRig.wearsGlasses)
        #expect(!straightRig.teethVisible)
        #expect(FaceRig.headTurnGain(turnRadians: straightRig.rest.turn) == 1)

        let tiltedRig = try await Self.mapped(tilted)
        Self.expectOrder(tiltedRig)
        let tilt = abs(tiltedRig.rest.tilt) * 180 / .pi
        #expect(abs(tilt - 20) < 10)

        let glassesRig = try await Self.mapped(glasses)
        Self.expectOrder(glassesRig)
        #expect(glassesRig.wearsGlasses)
        #expect(!glassesRig.teethVisible)

        let turnedRig = try await Self.mapped(turned)
        Self.expectOrder(turnedRig)
        #expect(FaceRig.headTurnGain(turnRadians: turnedRig.rest.turn) < 1)

        let teethRig = try await Self.mapped(teeth)
        Self.expectOrder(teethRig)
        #expect(teethRig.teethVisible)
        #expect(!teethRig.wearsGlasses)

        let smileRig = try await Self.mapped(smile)
        Self.expectOrder(smileRig)
        #expect(!smileRig.teethVisible)
    }

    private static func mapped(_ image: UIImage) async throws -> FaceRig {
        let result = await FaceMapper.map(image)
        return try #require(result.rig)
    }

    private static func expectOrder(_ rig: FaceRig) {
        let left = rig.position(of: .leftEyeCenter)
        let right = rig.position(of: .rightEyeCenter)
        let nose = rig.position(of: .noseTip)
        let lips = rig.position(of: .upperLip)
        let chin = rig.position(of: .chin)
        #expect(left != nil && right != nil && nose != nil && lips != nil && chin != nil)
        if let left, let right, let nose, let lips, let chin {
            #expect(left.y < nose.y)
            #expect(right.y < nose.y)
            #expect(nose.y < lips.y)
            #expect(lips.y < chin.y)
            #expect(left.x != right.x)
            #expect(min(left.x, right.x) < nose.x && nose.x < max(left.x, right.x))
        }
    }

    private static func portrait(_ name: String) throws -> UIImage {
        try #require(UIImage(named: name))
    }

    private static func frontFace(roll: Double, yaw: Double, id: Int = 0, scale: CGFloat = 1) -> MappedFace {
        func points(_ pairs: [(CGFloat, CGFloat)]) -> [CGPoint] {
            pairs.map { CGPoint(x: 0.5 + ($0.0 - 0.5) * scale, y: 0.5 + ($0.1 - 0.5) * scale) }
        }
        let leftEye = points([(0.58, 0.38), (0.66, 0.38), (0.62, 0.36), (0.62, 0.40)])
        let rightEye = points([(0.34, 0.38), (0.42, 0.38), (0.38, 0.36), (0.38, 0.40)])
        var regions: [FaceRegion: FaceSample] = [
            .leftEye: FaceSample(points: leftEye, confidence: 0.9),
            .rightEye: FaceSample(points: rightEye, confidence: 0.9),
            .leftPupil: FaceSample(points: [CGPoint(x: 0.5 + 0.12 * scale, y: 0.5 - 0.12 * scale)], confidence: 0.9),
            .rightPupil: FaceSample(points: [CGPoint(x: 0.5 - 0.12 * scale, y: 0.5 - 0.12 * scale)], confidence: 0.9),
            .leftEyebrow: FaceSample(points: points([(0.56, 0.30), (0.62, 0.29), (0.68, 0.31)]), confidence: 0.8),
            .rightEyebrow: FaceSample(points: points([(0.32, 0.31), (0.38, 0.29), (0.44, 0.30)]), confidence: 0.8),
            .nose: FaceSample(points: points([(0.50, 0.48), (0.50, 0.56)]), confidence: 0.8),
            .outerLips: FaceSample(points: points([(0.42, 0.66), (0.50, 0.64), (0.58, 0.66), (0.50, 0.70)]), confidence: 0.2),
            .innerLips: FaceSample(points: points([(0.46, 0.66), (0.54, 0.66), (0.50, 0.68)]), confidence: 0.8),
            .faceContour: FaceSample(points: points([
                (0.28, 0.42), (0.30, 0.62), (0.40, 0.78), (0.50, 0.84), (0.60, 0.78), (0.70, 0.62), (0.72, 0.42)
            ]), confidence: 0.9)
        ]
        _ = regions
        return MappedFace(
            id: id,
            bounds: CGRect(x: 0.5 - 0.24 * scale, y: 0.5 - 0.28 * scale, width: 0.48 * scale, height: 0.56 * scale),
            roll: roll,
            yaw: yaw,
            pitch: 0,
            confidence: 0.95,
            regions: regions
        )
    }

    private static func memory(id: Int, savedAt: Date) -> PhotoMemory {
        let face = frontFace(roll: 0, yaw: 0, id: id)
        let rig = FaceRigBuilder.build(from: face, wearsGlasses: false, teethVisible: false)!
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        pixels[id] = UInt8(id)
        let fingerprint = PhotoFingerprint.make(pixels: pixels, width: 8, height: 8)!
        return PhotoMemory(
            fingerprint: fingerprint,
            strength: PhotoMemory.defaultStrength,
            calibration: nil,
            rig: rig,
            savedAt: savedAt
        )
    }

    private static func pattern(size: CGSize, cropped: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 8, y: 8, width: 24, height: 24))
            UIColor.red.setFill()
            context.fill(CGRect(x: size.width - 36, y: 12, width: 20, height: 40))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 20, y: size.height - 40, width: 50, height: 18))
            if cropped {
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width * 0.45, height: size.height))
            }
        }
    }

    private static func solid(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in
            color.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8)).fill()
        }
    }

    private static func isRed(_ image: UIImage) -> Bool {
        guard let pixel = PhotoFingerprint.rgbaPixels(of: image)?.bytes, pixel.count >= 3 else { return false }
        return pixel[0] > 200 && pixel[2] < 40
    }

    private static func isBlue(_ image: UIImage) -> Bool {
        guard let pixel = PhotoFingerprint.rgbaPixels(of: image)?.bytes, pixel.count >= 3 else { return false }
        return pixel[2] > 200 && pixel[0] < 40
    }

    private static func encoded(_ image: UIImage, type: UTType, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func image(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: image)
    }
}
