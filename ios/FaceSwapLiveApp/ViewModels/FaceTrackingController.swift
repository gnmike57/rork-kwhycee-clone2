import Foundation
import Observation
import UIKit

/// Owns face tracking end to end: which source runs, when it is allowed to,
/// and the single blended pose the 30 fps draw reads.
///
/// Readings from either source are smoothed, re-centred on the calibrated
/// rest pose, resampled onto the draw clock and blended with the idle so the
/// face never freezes mid-expression. Nothing here knows about ARKit or the
/// network; those live behind `FaceSourceEvent`.
@Observable
@MainActor
final class FaceTrackingController {
    /// The draw's fixed rate.
    static let drawRate: Double = 30

    /// How far behind real time the draw samples, so there is a reading on
    /// both sides to blend between.
    static let renderLatency: TimeInterval = 1 / drawRate

    private static let modeKey = "faceTracking.mode"
    private static let portKey = "faceTracking.port"

    // MARK: - Settings

    /// Where readings come from. Switching restarts a running source.
    var mode: FaceTrackingMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            restartIfRunning()
        }
    }

    /// UDP port for Live Link Face packets.
    var port: UInt16 {
        didSet {
            guard port != oldValue else { return }
            defaults.set(Int(port), forKey: Self.portKey)
            if mode == .secondPhone { restartIfRunning() }
        }
    }

    /// The user's switch. Not remembered across launches: the camera should
    /// never come on by itself.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            reconcile()
        }
    }

    // MARK: - Lifecycle gate

    /// A still is being drawn into a feed the page is pulling.
    var stillOnActiveFeed = false {
        didSet {
            guard stillOnActiveFeed != oldValue else { return }
            reconcile()
        }
    }

    /// The app is on screen.
    var isForeground = true {
        didSet {
            guard isForeground != oldValue else { return }
            reconcile()
        }
    }

    /// Another screen wants the camera (the Preview tab).
    var isCameraNeededElsewhere = false {
        didSet {
            guard isCameraNeededElsewhere != oldValue else { return }
            reconcile()
        }
    }

    /// Everything the gate needs is true.
    var isAllowedToRun: Bool {
        isEnabled && stillOnActiveFeed && isForeground && !isCameraNeededElsewhere
    }

    // MARK: - Outputs

    private(set) var state: FaceTrackingState = .off

    /// The pose to draw, refreshed 30 times a second while a source runs.
    private(set) var outputPose: FacePose = .neutral

    /// The newest smoothed, calibrated reading — for meters.
    private(set) var latestTrackedPose: FacePose?

    /// Readings in the last second.
    private(set) var readingsPerSecond: Int = 0

    /// The second iPhone's name, once a packet has arrived.
    private(set) var senderName: String?

    /// Addresses a second iPhone can send to.
    private(set) var addresses: [LocalAddress] = []

    /// 0…1 while calibrating, nil otherwise.
    private(set) var calibrationProgress: Double?

    /// The rest pose readings are re-centred on.
    private(set) var neutralBaseline: FacePose?

    /// True while the output is the idle rather than a tracked face.
    private(set) var isIdling = true

    // MARK: - Private

    private let defaults: UserDefaults
    private var arkit: ARKitFaceSource?
    private var liveLink: LiveLinkListener?
    private var readerTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var isSourceRunning = false
    private var isInterrupted = false

    private var smoother = PoseSmoother()
    private var resampler = PoseResampler()
    private var mixer = PoseMixer()
    private var idle = IdlePoseGenerator(seed: 0x5EED_FACE, startingAt: FaceClock.now())
    private var calibrator = NeutralCalibrator()

    private var lastPoseAt: TimeInterval?
    private var lastPacketAt: TimeInterval?
    private var everHadReading = false
    private var recentReadings: [TimeInterval] = []
    private var tickCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = FaceTrackingMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .thisPhone
        let storedPort = defaults.integer(forKey: Self.portKey)
        port = (1...Int(UInt16.max)).contains(storedPort) ? UInt16(storedPort) : LiveLinkFacePacket.defaultPort
    }

    // MARK: - Calibration

    /// Starts the two-second neutral hold. Ignored unless a face is being read.
    func calibrateNeutral() {
        guard state.isTracking else { return }
        calibrator.begin(at: FaceClock.now())
        calibrationProgress = 0
    }

    func cancelCalibration() {
        calibrator.cancel()
        calibrationProgress = nil
    }

    func clearNeutralBaseline() {
        neutralBaseline = nil
    }

    /// Reuses a baseline remembered for a photo.
    func setNeutralBaseline(_ baseline: FacePose?) {
        neutralBaseline = baseline
    }

    // MARK: - Gate

    private func reconcile() {
        if isAllowedToRun {
            if !isSourceRunning { startSource() }
        } else {
            if isSourceRunning { stopSource() }
            state = isEnabled ? .standby : .off
        }
    }

    private func restartIfRunning() {
        guard isSourceRunning else { return }
        stopSource()
        reconcile()
    }

    private func startSource() {
        isSourceRunning = true
        isInterrupted = false
        resetPipeline()
        state = .starting

        switch mode {
        case .thisPhone:
            guard ARKitFaceSource.isSupported else {
                state = .unavailable(.notSupported)
                isSourceRunning = false
                return
            }
            let source = ARKitFaceSource()
            arkit = source
            consume(source.events)
            startTask = Task { [weak self] in
                await source.start()
                guard let self, !Task.isCancelled else { return }
                self.updateInterfaceOrientation()
            }
        case .secondPhone:
            let listener = LiveLinkListener()
            liveLink = listener
            addresses = LocalNetworkAddresses.current()
            consume(listener.events)
            let port = port
            startTask = Task {
                await listener.start(port: port)
            }
        }

        startTicking()
    }

    private func stopSource() {
        tickTask?.cancel()
        tickTask = nil
        startTask?.cancel()
        startTask = nil
        readerTask?.cancel()
        readerTask = nil

        if let arkit {
            arkit.stop()
            self.arkit = nil
        }
        if let liveLink {
            Task { await liveLink.stop() }
            self.liveLink = nil
        }

        isSourceRunning = false
        cancelCalibration()
        resetPipeline()
        outputPose = .neutral
        isIdling = true
    }

    private func resetPipeline() {
        smoother.reset()
        resampler.reset()
        mixer.reset()
        lastPoseAt = nil
        lastPacketAt = nil
        everHadReading = false
        recentReadings.removeAll()
        latestTrackedPose = nil
        readingsPerSecond = 0
        senderName = nil
    }

    // MARK: - Source events

    private func consume(_ events: AsyncStream<FaceSourceEvent>) {
        readerTask?.cancel()
        readerTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: FaceSourceEvent) {
        guard isSourceRunning else { return }
        let now = FaceClock.now()

        switch event {
        case .pose(let pose, let sender):
            if let sender { senderName = sender }
            lastPacketAt = now
            everHadReading = true
            guard pose.hasFace else {
                smoother.reset()
                return
            }
            let smoothed = smoother.smooth(pose)
            if calibrator.isRunning {
                if let baseline = calibrator.add(smoothed, at: now) {
                    neutralBaseline = baseline
                    calibrationProgress = nil
                    Haptics.snap()
                } else {
                    calibrationProgress = calibrator.progress(at: now)
                }
            }
            let calibrated = neutralBaseline.map { smoothed.calibrated(against: $0) } ?? smoothed
            resampler.add(calibrated)
            latestTrackedPose = calibrated
            lastPoseAt = pose.timestamp
            recentReadings.append(now)

        case .searching:
            smoother.reset()
            if state == .starting { transition(to: .searching) }

        case .interrupted:
            isInterrupted = true
            smoother.reset()
            transition(to: .lost)

        case .resumed:
            isInterrupted = false

        case .listening:
            if state == .starting { transition(to: .listening) }

        case .portUnavailable(let port):
            fail(.portInUse(port))

        case .cameraDenied:
            fail(.cameraDenied)

        case .failed(let reason):
            fail(.failed(reason))
        }
    }

    private func fail(_ problem: FaceTrackingState.Problem) {
        stopSource()
        state = .unavailable(problem)
    }

    // MARK: - 30 fps tick

    private func startTicking() {
        tickTask?.cancel()
        tickCount = 0
        tickTask = Task { [weak self] in
            let clock = ContinuousClock()
            let period = Duration.seconds(1 / Self.drawRate)
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
                let now = clock.now
                if next < now { next = now + period }
            }
        }
    }

    private func tick() {
        guard isSourceRunning else { return }
        let now = FaceClock.now()
        tickCount += 1

        let tracked = resampler.sample(at: now - Self.renderLatency)
        mixer.advance(to: now, lastPoseAt: lastPoseAt)
        let idlePose = idle.pose(at: now)
        outputPose = mixer.mix(tracked: tracked, idle: idlePose)
        isIdling = mixer.isIdling

        let window = now - 1
        recentReadings.removeAll { $0 < window }
        readingsPerSecond = recentReadings.count

        if calibrator.isRunning {
            calibrationProgress = calibrator.progress(at: now)
        }

        updateState(at: now)

        if tickCount % 30 == 0 {
            updateInterfaceOrientation()
        }
        if mode == .secondPhone, tickCount % 150 == 0 {
            addresses = LocalNetworkAddresses.current()
        }
    }

    private func updateState(at now: TimeInterval) {
        if case .unavailable = state { return }
        if isInterrupted {
            transition(to: .lost)
            return
        }

        switch mode {
        case .thisPhone:
            guard let lastPoseAt else {
                if state == .live || state == .lost { transition(to: .lost) }
                return
            }
            let age = now - lastPoseAt
            transition(to: age < PoseMixer.freshWindow ? .live : .lost)

        case .secondPhone:
            guard let lastPacketAt else {
                if state == .receiving || state == .lost { transition(to: .lost) }
                return
            }
            let age = now - lastPacketAt
            transition(to: age < 1 ? .receiving : .lost)
        }
    }

    /// Changes state with the matching haptic: success on finding a face or
    /// a link, warning on losing one.
    private func transition(to newState: FaceTrackingState) {
        guard newState != state else { return }
        let wasTracking = state.isTracking
        state = newState
        if newState.isTracking, !wasTracking {
            Haptics.success()
        } else if newState == .lost, wasTracking {
            Haptics.warning()
            if calibrator.isRunning { cancelCalibration() }
        }
    }

    // MARK: - Orientation

    /// Head angles are read against the screen's up, so the front camera
    /// source is told how the phone is held.
    private func updateInterfaceOrientation() {
        guard let arkit else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        arkit.setInterfaceOrientation(scene?.interfaceOrientation ?? .portrait)
    }
}
