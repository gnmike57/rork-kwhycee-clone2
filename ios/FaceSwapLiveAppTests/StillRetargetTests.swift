import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import FaceSwapLiveApp

/// Stage 3: the living still retargets a live face onto the photo, and the
/// page never learns a new name.
@MainActor
struct StillRetargetTests {
    @Test func strengthZeroLeavesThePhotoMeshAlone() {
        let rig = try! #require(Self.rig())
        let drive = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.mouthSmileLeft] = 1 },
            strength: 0,
            headPosePresent: true
        )
        #expect(drive.vertices == rig.deformedVertices())
        #expect(drive.leftLid == 0)
        #expect(drive.jawOpen == 0)
        #expect(!drive.showTeeth)
    }

    @Test func smilingPhotoDoesNotDoubleANeutralLiveFace() {
        let rig = try! #require(Self.rig())
        let rest = rig.deformedVertices()
        let mouth = try! #require(rig.handleIndex[.mouthLeft])
        let drive = StillRetarget.drive(
            rig: rig,
            live: .neutral,
            rest: .neutral,
            strength: 1,
            headPosePresent: true
        )
        #expect(abs(drive.vertices[mouth].y - rest[mouth].y) < 0.004)
    }

    @Test func smilingLiveOnASmilingRestDoesNotAddAnotherSmile() {
        let rig = try! #require(Self.rig())
        let restMesh = rig.deformedVertices()
        let mouth = try! #require(rig.handleIndex[.mouthLeft])
        let smile = Self.pose { $0[.mouthSmileLeft] = 0.7 }
        let drive = StillRetarget.drive(rig: rig, live: smile, rest: smile, strength: 1, headPosePresent: false)
        #expect(abs(drive.vertices[mouth].y - restMesh[mouth].y) < 0.004)
    }

    @Test func neutralPhotoSmilesWhenTheLiveFaceSmiles() {
        let rig = try! #require(Self.rig(mouthConfidence: 0.9))
        let rest = rig.deformedVertices()
        let mouth = try! #require(rig.handleIndex[.mouthLeft])
        let full = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.mouthSmileLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        let half = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.mouthSmileLeft] = 1 },
            strength: 0.5,
            headPosePresent: false
        )
        let fullLift = rest[mouth].y - full.vertices[mouth].y
        let halfLift = rest[mouth].y - half.vertices[mouth].y
        #expect(fullLift > 0.015)
        #expect(halfLift > fullLift * 0.35)
        #expect(halfLift < fullLift * 0.7)
    }

    @Test func jawStaysInsideTheSoftEdge() {
        let rig = try! #require(Self.rig())
        let chin = try! #require(rig.handleIndex[.chin])
        let rest = rig.deformedVertices()
        let drive = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.jawOpen] = 1 },
            strength: 1,
            headPosePresent: false
        )
        let limit = StillRetarget.jawLimit(in: rig)
        #expect(drive.vertices[chin].y <= limit + 0.001)
        #expect(drive.vertices[chin].y > rest[chin].y + 0.01)
        #expect(drive.jawOpen > 0.5)
    }

    @Test func lidsDoNotInvert() {
        let rig = try! #require(Self.rig())
        let center = try! #require(rig.handleIndex[.leftEyeCenter])
        let drive = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.eyeBlinkLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        let lower = StillRetarget.lowerLidY(rig: rig, eye: .leftEyeCenter)
        #expect(drive.vertices[center].y <= lower + 0.001)
        #expect(drive.leftLid > 0.9)
    }

    @Test func headParallaxIsZeroWhenHeadWasNotSent() {
        let rig = try! #require(Self.rig())
        let nose = try! #require(rig.handleIndex[.noseTip])
        let rest = rig.deformedVertices()
        let hidden = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.headYaw] = 0.4 },
            strength: 1,
            headPosePresent: false
        )
        let shown = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.headYaw] = 0.4 },
            strength: 1,
            headPosePresent: true
        )
        #expect(abs(hidden.vertices[nose].x - rest[nose].x) < 0.002)
        #expect(abs(shown.vertices[nose].x - rest[nose].x) > 0.01)
    }

    @Test func turnedPhotoGetsLessHeadParallax() {
        let straight = try! #require(Self.rig(yaw: 0))
        let turned = try! #require(Self.rig(yaw: 30 * .pi / 180))
        let pose = Self.pose { $0[.headYaw] = 0.4 }
        let straightDrive = StillRetarget.drive(rig: straight, live: pose, strength: 1, headPosePresent: true)
        let turnedDrive = StillRetarget.drive(rig: turned, live: pose, strength: 1, headPosePresent: true)
        let straightNose = try! #require(straight.handleIndex[.noseTip])
        let turnedNose = try! #require(turned.handleIndex[.noseTip])
        let straightShift = abs(straightDrive.vertices[straightNose].x - straight.deformedVertices()[straightNose].x)
        let turnedShift = abs(turnedDrive.vertices[turnedNose].x - turned.deformedVertices()[turnedNose].x)
        #expect(FaceRig.headTurnGain(turnRadians: turned.rest.turn) < 1)
        #expect(turnedShift < straightShift)
    }

    @Test func glassesStayPutWhileTheIrisSlides() {
        let rig = try! #require(Self.rig(glasses: true))
        let rest = rig.deformedVertices()
        let outer = try! #require(rig.handleIndex[.leftEyeOuter])
        let pupil = try! #require(rig.handleIndex[.leftEyeCenter])
        let blinked = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.eyeBlinkLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(abs(blinked.vertices[outer].x - rest[outer].x) < 0.002)
        #expect(abs(blinked.vertices[outer].y - rest[outer].y) < 0.002)
        let looked = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.leftEyeYaw] = 0.4 },
            strength: 1,
            headPosePresent: false
        )
        #expect(abs(looked.vertices[pupil].x - rest[pupil].x) > 0.004)
    }

    @Test func aWeakMouthSoftensTheSmile() {
        let strong = try! #require(Self.rig(mouthConfidence: 0.9))
        let weak = try! #require(Self.rig(mouthConfidence: 0.2))
        let pose = Self.pose { $0[.mouthSmileLeft] = 1 }
        let strongLift = Self.lift(strong, pose)
        let weakLift = Self.lift(weak, pose)
        #expect(strongLift > 0.015)
        #expect(weakLift < strongLift * 0.5)
    }

    @Test func browsCheeksAndSquintFollow() {
        let rig = try! #require(Self.rig())
        let rest = rig.deformedVertices()
        let brow = try! #require(rig.handleIndex[.leftBrowCenter])
        let jaw = try! #require(rig.handleIndex[.leftJaw])
        let down = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.browDownLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(down.vertices[brow].y > rest[brow].y + 0.01)
        let puff = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.cheekPuff] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(puff.vertices[jaw].x > rest[jaw].x + 0.005)
        let squint = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.eyeSquintLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(squint.leftLid > 0.3)
    }

    @Test func blendSitsBetweenTheTwoPoses() {
        let rig = try! #require(Self.rig(mouthConfidence: 0.9))
        let mouth = try! #require(rig.handleIndex[.mouthLeft])
        let still = StillRetarget.drive(rig: rig, live: .neutral, strength: 1, headPosePresent: false)
        let smile = StillRetarget.drive(
            rig: rig,
            live: Self.pose { $0[.mouthSmileLeft] = 1 },
            strength: 1,
            headPosePresent: false
        )
        let mid = StillRetarget.blended(still, smile, amount: 0.5)
        let low = min(still.vertices[mouth].y, smile.vertices[mouth].y)
        let high = max(still.vertices[mouth].y, smile.vertices[mouth].y)
        #expect(mid.vertices[mouth].y > low + 0.004)
        #expect(mid.vertices[mouth].y < high - 0.004)
    }

    @Test func teethAppearOnlyWhenThePhotoShowsThem() {
        let closed = try! #require(Self.rig(teeth: true))
        let shut = StillRetarget.drive(rig: closed, live: .neutral, strength: 1, headPosePresent: false)
        #expect(!shut.showTeeth)
        let open = StillRetarget.drive(
            rig: closed,
            live: Self.pose { $0[.jawOpen] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(open.showTeeth)
        let noTeeth = try! #require(Self.rig(teeth: false))
        let bare = StillRetarget.drive(
            rig: noTeeth,
            live: Self.pose { $0[.jawOpen] = 1 },
            strength: 1,
            headPosePresent: false
        )
        #expect(!bare.showTeeth)
    }

    @Test func pageClockStaysAtThirtyAndIgnoresHeat() {
        #expect(StillRetarget.drawRate == 30)
        #expect(StillRetarget.followsHeat == false)
        #expect(FaceTrackingController.drawRate == 30)
        let size = StillRetarget.workingSize(for: CGSize(width: 4000, height: 3000))
        #expect(max(size.width, size.height) <= CGFloat(StillRetarget.maxLongSide))
        #expect(Int(size.width * size.height * 4) <= StillRetarget.bytesPerSlot)
    }

    @Test func deliveryDoesNotNameAFaceOrTouchFraming() {
        let script = StillDelivery.attachScript(port: 9)
            + StillDelivery.restoreScript()
            + StillDelivery.feedScript()
        #expect(!StillDelivery.mentionsFaceData(script))
        #expect(script.contains("127.0.0.1"))
        #expect(!script.contains("s.fc"))
        #expect(!script.contains("s.lzf"))
        let page = StyleSheetProvider.patchScript
        #expect(!page.contains("jawOpen"))
        #expect(!page.contains("127.0.0.1"))
        #expect(!page.contains("FaceTracking"))
    }

    @Test func strengthZeroPictureStaysThePhoto() {
        let rig = try! #require(Self.rig())
        let image = Self.solid(.red)
        let drive = StillRetarget.drive(rig: rig, live: .neutral, strength: 0, headPosePresent: false)
        let picture = try! #require(StillRenderer.picture(image: image, drive: drive, rig: rig))
        #expect(Self.isRed(picture))
    }

    private static func lift(_ rig: FaceRig, _ pose: FacePose) -> CGFloat {
        let mouth = rig.handleIndex[.mouthLeft]!
        let rest = rig.deformedVertices()
        let drive = StillRetarget.drive(rig: rig, live: pose, strength: 1, headPosePresent: false)
        return rest[mouth].y - drive.vertices[mouth].y
    }

    private static func pose(_ edit: (inout FacePose) -> Void) -> FacePose {
        var pose = FacePose.neutral
        pose.hasFace = true
        edit(&pose)
        return pose
    }

    private static func rig(
        mouthConfidence: Float = 0.9,
        yaw: Double = 0,
        glasses: Bool = false,
        teeth: Bool = false
    ) -> FaceRig? {
        FaceRigBuilder.build(
            from: face(mouthConfidence: mouthConfidence, yaw: yaw),
            wearsGlasses: glasses,
            teethVisible: teeth
        )
    }

    private static func face(mouthConfidence: Float, yaw: Double) -> MappedFace {
        func points(_ pairs: [(CGFloat, CGFloat)]) -> [CGPoint] {
            pairs.map { CGPoint(x: $0.0, y: $0.1) }
        }
        return MappedFace(
            id: 0,
            bounds: CGRect(x: 0.26, y: 0.22, width: 0.48, height: 0.56),
            roll: 0,
            yaw: yaw,
            pitch: 0,
            confidence: 0.95,
            regions: [
                .leftEye: FaceSample(points: points([(0.58, 0.38), (0.66, 0.38), (0.62, 0.36), (0.62, 0.40)]), confidence: 0.9),
                .rightEye: FaceSample(points: points([(0.34, 0.38), (0.42, 0.38), (0.38, 0.36), (0.38, 0.40)]), confidence: 0.9),
                .leftPupil: FaceSample(points: [CGPoint(x: 0.62, y: 0.38)], confidence: 0.9),
                .rightPupil: FaceSample(points: [CGPoint(x: 0.38, y: 0.38)], confidence: 0.9),
                .leftEyebrow: FaceSample(points: points([(0.56, 0.30), (0.62, 0.29), (0.68, 0.31)]), confidence: 0.8),
                .rightEyebrow: FaceSample(points: points([(0.32, 0.31), (0.38, 0.29), (0.44, 0.30)]), confidence: 0.8),
                .nose: FaceSample(points: points([(0.50, 0.48), (0.50, 0.56)]), confidence: 0.8),
                .outerLips: FaceSample(points: points([(0.42, 0.66), (0.50, 0.64), (0.58, 0.66), (0.50, 0.70)]), confidence: mouthConfidence),
                .innerLips: FaceSample(points: points([(0.46, 0.66), (0.54, 0.66), (0.50, 0.68)]), confidence: 0.8),
                .faceContour: FaceSample(points: points([
                    (0.28, 0.42), (0.30, 0.62), (0.40, 0.78), (0.50, 0.84), (0.60, 0.78), (0.70, 0.62), (0.72, 0.42)
                ]), confidence: 0.9)
            ]
        )
    }

    private static func solid(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { _ in
            color.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 32, height: 32)).fill()
        }
    }

    private static func isRed(_ image: UIImage) -> Bool {
        guard let pixel = PhotoFingerprint.rgbaPixels(of: image)?.bytes, pixel.count >= 3 else { return false }
        return pixel[0] > 200 && pixel[2] < 40
    }
}
