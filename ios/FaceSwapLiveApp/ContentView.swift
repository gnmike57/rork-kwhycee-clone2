import SwiftUI

enum AppTab: Hashable {
    case preview
    case browser
    case myVideos
    case diagnostics
    case profile
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var profileManager = DeviceProfileManager()
    @State private var videoLibrary = VideoLibraryService()
    @State private var browserViewModel = BrowserViewModel()
    @State private var faceTracking = FaceTrackingController()
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
            Tab("Diagnostics", systemImage: "waveform.badge.magnifyingglass", value: AppTab.diagnostics) {
                DiagnosticsView()
            }
            Tab("Profile", systemImage: "iphone.gen3", value: AppTab.profile) {
                ProfileSelectionView(profileManager: profileManager) {
                    hasSelectedProfile = true
                }
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
        .onChange(of: selectedTab, initial: true) { _, tab in
            faceTracking.setPreviewTabSelected(tab == .preview)
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
