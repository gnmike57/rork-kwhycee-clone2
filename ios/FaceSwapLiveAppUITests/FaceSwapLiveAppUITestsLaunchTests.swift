import XCTest

final class FaceSwapLiveAppUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchReachesTheFirstScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let profiles = app.descendants(matching: .any)["device-profiles"]
        let main = app.descendants(matching: .any)["main-app"]
        let title = app.staticTexts["Device Profiles"]
        let reachedProfiles = profiles.waitForExistence(timeout: 12) || title.waitForExistence(timeout: 2)
        let reachedMain = main.waitForExistence(timeout: 2)
        XCTAssertTrue(
            reachedProfiles || reachedMain,
            "Launch should reach Device Profiles or the main app, not a blank window"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
