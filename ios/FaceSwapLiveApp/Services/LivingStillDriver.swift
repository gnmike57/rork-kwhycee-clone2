import Foundation
import UIKit
import WebKit

/// Draws the living still at 30 fps and hands the picture to the page.
///
/// The page's own clock is not touched. Heat may slow tracking; it does not
/// slow this draw. Face numbers stay on the phone.
@MainActor
final class LivingStillDriver {
    private weak var viewModel: BrowserViewModel?
    private weak var tracking: FaceTrackingController?
    private let server = StillFrameServer()
    private var task: Task<Void, Never>?
    private var previous: StillDrive?
    private var attached = false
    private var pollInFlight = false
    private var pollMisses = 0
    private var lastGeneration = 0
    private var tickCount = 0
    private var strengthCache: [ObjectIdentifier: Double] = [:]

    func start(viewModel: BrowserViewModel, tracking: FaceTrackingController) {
        guard LivingStills.isAvailable else { return }
        self.viewModel = viewModel
        self.tracking = tracking
        task?.cancel()
        task = Task { [weak self] in
            let clock = ContinuousClock()
            let period = Duration.seconds(1 / StillRetarget.drawRate)
            var next = clock.now + period
            while !Task.isCancelled {
                do {
                    try await clock.sleep(until: next, tolerance: .milliseconds(2))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                self.tick()
                next += period
                if next < clock.now { next = clock.now + period }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        restoreIfNeeded()
        server.stop()
        viewModel?.livingPreview = nil
    }

    private func tick() {
        guard let viewModel, let tracking else { return }
        tickCount += 1
        if tickCount % 30 == 0 { pollFeed() }
        if viewModel.mediaGeneration != lastGeneration {
            lastGeneration = viewModel.mediaGeneration
            attached = false
        }

        guard let still = activeStill(in: viewModel),
              let rig = viewModel.frameCache.rig(for: still.image) else {
            if stillNeedsMap(in: viewModel) { return }
            idle()
            return
        }
        let strength = strength(for: still.image, in: viewModel)
        let pose = tracking.outputPose
        let drive = StillRetarget.drive(
            rig: rig,
            live: pose,
            rest: .neutral,
            strength: strength,
            headPosePresent: !tracking.isExpressionOnly
        )
        let frame = previous.map { StillRetarget.blended($0, drive, amount: 0.65) } ?? drive
        previous = drive

        let wantsPage = shouldFeedPage(tracking: tracking, strength: strength, drive: drive, rig: rig)
        let wantsPreview = viewModel.frameCheckRequest != nil && tracking.isEnabled && strength > 0.001
        guard wantsPage || wantsPreview else {
            idle()
            return
        }

        guard let picture = StillRenderer.picture(image: still.image, drive: frame, rig: rig) else { return }
        if wantsPreview {
            viewModel.livingPreview = picture
        }
        guard wantsPage, let jpeg = picture.jpegData(compressionQuality: 0.72) else { return }
        server.start()
        server.publish(jpeg)
        attachIfNeeded()
    }

    private func idle() {
        restoreIfNeeded()
        previous = nil
        if viewModel?.livingPreview != nil {
            viewModel?.livingPreview = nil
        }
    }

    private func shouldFeedPage(
        tracking: FaceTrackingController,
        strength: Double,
        drive: StillDrive,
        rig: FaceRig
    ) -> Bool {
        guard tracking.isEnabled, strength > 0.001, viewModel?.stillOnActiveFeed == true else { return false }
        if attached { return true }
        if tracking.state.isTracking || tracking.state == .lost { return !StillRetarget.isIdentity(drive, rest: rig.deformedVertices()) }
        return tracking.outputPose.isMoving && !StillRetarget.isIdentity(drive, rest: rig.deformedVertices())
    }

    private func activeStill(in viewModel: BrowserViewModel) -> (image: UIImage, facing: BrowserViewModel.CameraFacing, slot: Int)? {
        if let feed = viewModel.livingFeed,
           viewModel.isStill(facing: feed.facing, slot: feed.slot),
           let image = viewModel.previewImage(facing: feed.facing, slot: feed.slot) {
            return (image, feed.facing, feed.slot)
        }
        if viewModel.isLiveStreamActive, let facing = viewModel.activeStreamFacing {
            let slot = facing == .back ? viewModel.backQueueIndex : viewModel.frontQueueIndex
            if viewModel.isStill(facing: facing, slot: slot),
               let image = viewModel.previewImage(facing: facing, slot: slot) {
                return (image, facing, slot)
            }
        }
        if let request = viewModel.frameCheckRequest,
           viewModel.isStill(facing: request.facing, slot: request.slot),
           let image = viewModel.previewImage(facing: request.facing, slot: request.slot) {
            return (image, request.facing, request.slot)
        }
        return nil
    }

    private func stillNeedsMap(in viewModel: BrowserViewModel) -> Bool {
        guard let still = activeStill(in: viewModel),
              viewModel.frameCache.rig(for: still.image) == nil,
              !viewModel.frameCache.hasSearchedMap(for: still.image) else { return false }
        viewModel.ensureFaceMap(for: still.image)
        return true
    }

    private func strength(for image: UIImage, in viewModel: BrowserViewModel) -> Double {
        let key = ObjectIdentifier(image)
        if let cached = strengthCache[key] { return cached }
        let value: Double
        if let fingerprint = PhotoFingerprint.make(from: image),
           let memory = viewModel.photoMemory.match(fingerprint) {
            value = min(1, max(0, memory.strength))
        } else {
            value = PhotoMemory.defaultStrength
        }
        strengthCache[key] = value
        return value
    }

    private func pollFeed() {
        guard let webView = viewModel?.webView, !pollInFlight else { return }
        pollInFlight = true
        webView.evaluateJavaScript(StillDelivery.feedScript()) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                self.pollInFlight = false
                self.applyFeed(result as? String)
            }
        }
    }

    private func applyFeed(_ answer: String?) {
        guard let answer else {
            pollMisses += 1
            if pollMisses > 3 { viewModel?.livingFeed = nil }
            return
        }
        pollMisses = 0
        let parts = answer.split(separator: ":")
        guard parts.count == 2, let slot = Int(parts[1]) else {
            if answer == "idle" || answer == "other" { viewModel?.livingFeed = nil }
            return
        }
        let facing: BrowserViewModel.CameraFacing = parts[0] == "b" ? .back : .front
        viewModel?.livingFeed = LivingFeedSignal(facing: facing, slot: slot)
    }

    private func attachIfNeeded() {
        guard !attached, let port = server.port, let webView = viewModel?.webView else { return }
        attached = true
        webView.evaluateJavaScript(StillDelivery.attachScript(port: port)) { [weak self] result, _ in
            Task { @MainActor in
                if (result as? String) == "idle" {
                    self?.attached = false
                }
            }
        }
    }

    private func restoreIfNeeded() {
        guard attached, let webView = viewModel?.webView else {
            attached = false
            return
        }
        attached = false
        webView.evaluateJavaScript(StillDelivery.restoreScript(), completionHandler: nil)
    }
}
