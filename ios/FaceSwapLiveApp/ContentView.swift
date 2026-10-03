import SwiftUI

enum AppTab: Hashable {
    case preview
    case browser
    case myVideos
    case liveLink
    case settings
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var profileManager = DeviceProfileManager()
    @State private var videoLibrary = VideoLibraryService()
    @State private var browserViewModel = BrowserViewModel()
    @State private var faceTracking = FaceTrackingController()
    @State private var livingStill = LivingStillDriver()
    @State private var hasSelectedProfile: Bool = false
    @State private var selectedTab: AppTab = .browser

    var body: some View {
        Group {
            if profileManager.hasActiveProfile && hasSelectedProfile {
                mainAppView
            } else {
                ProfileSelectionView(profileManager: profileManager) {
                    withAnimation(.spring(duration: 0.4)) {
                        hasSelectedProfile = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            hasSelectedProfile = profileManager.hasActiveProfile
        }
    }

    private var mainAppView: some View {
        TabView(selection: $selectedTab) {
            Tab("Preview", systemImage: "photo.fill", value: AppTab.preview) {
                LivePreviewView()
            }
            Tab("Browser", systemImage: "globe", value: AppTab.browser) {
                BrowserContentView(profileManager: profileManager, viewModel: browserViewModel) {
                    selectedTab = .myVideos
                }
            }
            Tab("My Media", systemImage: "photo.on.rectangle.angled", value: AppTab.myVideos) {
                MyMediaView(
                    videoLibrary: videoLibrary,
                    browserViewModel: browserViewModel,
                    onSelectSequence: { video, facing, slot in
                        browserViewModel.loadSavedVideo(video, facing: facing, slot: slot)
                    },
                    isSlotOneFilled: { facing in
                        facing == .front
                            ? browserViewModel.frontSourceType != nil
                            : browserViewModel.backSourceType != nil
                    }
                )
            }
            Tab("Live Link", systemImage: faceTracking.tabSymbol, value: AppTab.liveLink) {
                LiveLinkTabView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(profileManager: profileManager, browserViewModel: browserViewModel)
            }
        }
        .environment(profileManager)
        .environment(videoLibrary)
        .environment(faceTracking)
        // Face tracking only runs while a still is on an active feed, the app
        // is on screen and the Preview tab is not holding the camera.
        .onChange(of: browserViewModel.stillOnActiveFeed, initial: true) { _, isStill in
            faceTracking.stillOnActiveFeed = isStill
        }
        .onAppear {
            livingStill.start(viewModel: browserViewModel, tracking: faceTracking)
        }
        .onChange(of: browserViewModel.behavior.settings.faceTrackingHaptics, initial: true) { _, on in
            faceTracking.isHapticsEnabled = on
        }
        .onChange(of: selectedTab, initial: true) { _, tab in
            faceTracking.setPreviewTabSelected(tab == .preview)
        }
        // The Face Tracking sheet's "Open Live Link" lands here.
        .onChange(of: browserViewModel.opensLiveLinkTab) { _, wantsLiveLink in
            guard wantsLiveLink else { return }
            browserViewModel.opensLiveLinkTab = false
            selectedTab = .liveLink
        }
        .accessibilityIdentifier(profileManager.hasActiveProfile && hasSelectedProfile ? "main-app" : "device-profiles")
        .onChange(of: scenePhase, initial: true) { _, phase in
            faceTracking.isForeground = phase == .active
        }
        // One presentation point for Frame Check, whichever tab asked for it.
        .fullScreenCover(item: $browserViewModel.frameCheckRequest) { request in
            FrameCheckEditorView(viewModel: browserViewModel, request: request)
        }
    }
}
