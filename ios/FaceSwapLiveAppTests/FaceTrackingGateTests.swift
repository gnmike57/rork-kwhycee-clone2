import Foundation
import Testing
@testable import FaceSwapLiveApp

/// The lifecycle gate: tracking may only run while a still sits on a feed the
/// page is pulling, the app is on screen and nothing else holds the camera.
@MainActor
struct FaceTrackingGateTests {
    private static func freshDefaults() -> UserDefaults {
        let name = "FaceTrackingGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func stillOnActiveFeedNeedsAnActiveFeedAndAStillInTheCurrentSlot() {
        let browser = BrowserViewModel()
        #expect(!browser.stillOnActiveFeed, "nothing loaded, no feed")

        browser.frontSourceType = .image
        #expect(!browser.stillOnActiveFeed, "a still loaded but the page is not pulling a feed")

        browser.isLiveStreamActive = true
        browser.activeStreamFacing = .front
        #expect(browser.stillOnActiveFeed)

        browser.frontSourceType = .video
        #expect(!browser.stillOnActiveFeed, "a video in the slot has nothing for face tracking")

        browser.frontSourceType = .image
        browser.activeStreamFacing = .back
        #expect(!browser.stillOnActiveFeed, "the page is pulling the back camera, whose slot is empty")

        browser.backSourceType = .image
        #expect(browser.stillOnActiveFeed)

        browser.isLiveStreamActive = false
        #expect(!browser.stillOnActiveFeed)
    }

    @Test func controllerOnlyRunsWhenEveryGateInputAllowsIt() {
        let controller = FaceTrackingController(defaults: Self.freshDefaults())
        #expect(controller.state == .off)
        #expect(!controller.isAllowedToRun)

        controller.isEnabled = true
        #expect(controller.state == .standby, "on, but no still on an active feed")

        // The gate is never fully opened here: that would start a real source.
        controller.isCameraNeededElsewhere = true
        controller.stillOnActiveFeed = true
        #expect(!controller.isAllowedToRun, "the Preview tab holds the camera")
        #expect(controller.state == .standby)

        controller.isForeground = false
        controller.isCameraNeededElsewhere = false
        #expect(!controller.isAllowedToRun, "backgrounded")
        #expect(controller.state == .standby)

        controller.isForeground = true
        controller.stillOnActiveFeed = false
        #expect(!controller.isAllowedToRun, "the still left the feed")
        #expect(controller.state == .standby)

        controller.isEnabled = false
        #expect(controller.state == .off)
    }

    @Test func modeAndPortAreRememberedButTheSwitchIsNot() {
        let defaults = Self.freshDefaults()
        let first = FaceTrackingController(defaults: defaults)
        #expect(first.mode == .thisPhone)
        #expect(first.port == LiveLinkFacePacket.defaultPort)

        first.mode = .secondPhone
        first.port = 12_000
        first.isEnabled = true

        let second = FaceTrackingController(defaults: defaults)
        #expect(second.mode == .secondPhone)
        #expect(second.port == 12_000)
        #expect(!second.isEnabled, "the camera must never come on by itself at launch")
    }

    @Test func statesReportWhatTheyMean() {
        #expect(FaceTrackingState.live.isTracking)
        #expect(FaceTrackingState.receiving.isTracking)
        #expect(!FaceTrackingState.lost.isTracking)
        #expect(FaceTrackingState.lost.isSourceActive)
        #expect(FaceTrackingState.listening.isSourceActive)
        #expect(!FaceTrackingState.standby.isSourceActive)
        #expect(!FaceTrackingState.unavailable(.portInUse(11111)).isSourceActive)
        #expect(FaceTrackingState.unavailable(.portInUse(11111)).label.contains("11111"))
    }

    @Test func interfaceKindsPickOutWifiAndHotspot() {
        #expect(LocalNetworkAddresses.kind(forInterface: "en0") == .wifi)
        #expect(LocalNetworkAddresses.kind(forInterface: "bridge100") == .hotspot)
        #expect(LocalNetworkAddresses.kind(forInterface: "en2") == .wired)
        #expect(LocalNetworkAddresses.kind(forInterface: "pdp_ip0") == nil)
        #expect(LocalNetworkAddresses.kind(forInterface: "utun3") == nil)
        #expect(LocalNetworkAddresses.kind(forInterface: "lo0") == nil)
        #expect(LocalNetworkAddresses.kind(forInterface: "awdl0") == nil)
    }
}
