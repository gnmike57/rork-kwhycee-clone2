import SwiftUI

struct BrowserContentView: View {
    let profileManager: DeviceProfileManager
    /// Owned by ContentView so the My Media tab can assign media to sequences.
    @Bindable var viewModel: BrowserViewModel
    var onOpenMyVideos: (() -> Void)?
    @FocusState private var isURLBarFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            progressBar
            browserContent
            bottomToolbar
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $viewModel.showBookmarks) {
            BookmarksSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDownloads) {
            DownloadsSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showOverlayPanel, onDismiss: {
            // Chained off the real dismissal, so the audit sheet cannot be missed.
            if viewModel.opensDeviceProfileAfterDismiss {
                viewModel.opensDeviceProfileAfterDismiss = false
                viewModel.showDeviceProfile = true
            }
            // Same hand-over for Frame Check, which the app root presents.
            if let request = viewModel.frameCheckAfterDismiss {
                viewModel.frameCheckAfterDismiss = nil
                viewModel.frameCheckRequest = request
            }
            // And for the My Media tab, which the app root owns.
            if viewModel.opensMyMediaAfterDismiss {
                viewModel.opensMyMediaAfterDismiss = false
                onOpenMyVideos?()
            }
        }) {
            OverlayControlSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDeviceProfile) {
            DeviceAuditProfileView(store: viewModel.behavior, viewModel: viewModel)
        }
        .sheet(item: $viewModel.pendingRecap) { recap in
            SequenceRecapView(recap: recap) {
                viewModel.pendingRecap = nil
                viewModel.injectSession.reset()
            }
        }
        .confirmationDialog(
            "Burn All Data",
            isPresented: $viewModel.showBurnConfirmation,
            titleVisibility: .visible
        ) {
            Button("Burn Everything", role: .destructive) {
                Task {
                    await viewModel.burnEverything()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently destroy all browsing history, cookies, cache, website data, bookmarks, and loaded media. This cannot be undone.")
        }
        .overlay {
            if viewModel.isBurning {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce.byLayer, options: .repeating)
                        Text("Burning all data...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .allowsHitTesting(true)
            }
        }
        .onAppear {
            viewModel.activeProfile = profileManager.activeProfile
        }
        .onChange(of: profileManager.activeProfileID) { _, _ in
            viewModel.activeProfile = profileManager.activeProfile
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: viewModel.isLoading ? "arrow.clockwise" : (viewModel.isMediaActive ? "video.fill" : "magnifyingglass"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.isMediaActive ? Color.green : .secondary)
                    .frame(width: 28)

                TextField("Search or enter URL", text: $viewModel.urlText)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.webSearch)
                    .focused($isURLBarFocused)
                    .onSubmit {
                        viewModel.navigateTo(viewModel.urlText)
                        isURLBarFocused = false
                    }

                if !viewModel.urlText.isEmpty && isURLBarFocused {
                    Button {
                        viewModel.urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(Color(.tertiarySystemFill))
            .clipShape(.rect(cornerRadius: 10))

            if isURLBarFocused {
                Button("Cancel") {
                    isURLBarFocused = false
                    if let url = viewModel.currentURL {
                        viewModel.urlText = url.absoluteString
                    }
                }
                .font(.system(size: 15))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.spring(duration: 0.25), value: isURLBarFocused)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            if viewModel.isLoading {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * viewModel.estimatedProgress, height: 2)
                    .animation(.linear(duration: 0.2), value: viewModel.estimatedProgress)
            }
        }
        .frame(height: 2)
    }

    private var browserContent: some View {
        ZStack {
            if viewModel.currentURL != nil {
                BrowserWebContainer(viewModel: viewModel)
            } else {
                startPage
            }

            if viewModel.isOverlayActive {
                overlayLayer
            }

            // Floating layers carry their own animation so the page underneath is
            // never nudged when the pill or a card appears.
            floatingLayers
        }
    }

    @ViewBuilder
    private var floatingLayers: some View {
        ZStack {
            // Nothing to control until a page is actually open.
            if viewModel.behavior.settings.showControlPill, viewModel.currentURL != nil {
                MediaControlPill(
                    viewModel: viewModel,
                    isHidden: isURLBarFocused || viewModel.pendingPrompt != nil,
                    onOpenSources: onOpenMyVideos
                ) { _ in
                    // Settings only. Tapping a camera never changes which camera
                    // a site gets when it does not ask for one.
                    viewModel.showOverlayPanel = true
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            if shouldShowHUD, let snapshot = viewModel.observedFeed {
                VStack {
                    HStack {
                        ObservedHUDView(snapshot: snapshot)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 10)
                .padding(.leading, 12)
                .transition(.opacity)
            }

            if let prompt = viewModel.pendingPrompt {
                promptLayer(prompt)
            }

            if let toastItem = viewModel.downloadService.activeToastItem {
                VStack {
                    Spacer()
                    DownloadToastView(
                        item: toastItem,
                        onCancel: { viewModel.downloadService.cancel(itemID: toastItem.id) },
                        onOpenList: {
                            viewModel.downloadService.dismissToast()
                            viewModel.showDownloads = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.behavior.settings.showControlPill)
        .animation(.spring(duration: 0.3), value: viewModel.pendingPrompt?.id)
        .animation(.easeOut(duration: 0.2), value: shouldShowHUD)
        .animation(.spring(duration: 0.3), value: viewModel.downloadService.activeToastID)
    }

    private var shouldShowHUD: Bool {
        viewModel.behavior.settings.showObservedHUD
            && viewModel.isMediaActive
            && viewModel.currentURL != nil
            && viewModel.pendingPrompt == nil
            && !isURLBarFocused
            && (viewModel.observedFeed?.isActive == true || viewModel.observedFeed?.pageHoldsFeed == true)
    }

    private func promptLayer(_ prompt: MediaRequestPrompt) -> some View {
        VStack {
            Spacer()
            MediaRequestPromptCard(
                prompt: prompt,
                viewModel: viewModel,
                holdSeconds: viewModel.behavior.settings.promptHoldSeconds,
                onResolve: { decision in
                    viewModel.resolvePrompt(id: prompt.id, decision: decision)
                },
                onSilenceHost: {
                    viewModel.behavior.silence(host: prompt.host)
                }
            )
            .padding(.bottom, 16)
        }
        .id(prompt.id)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var startPage: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.tertiary)

                    Text("Browser")
                        .font(.title2.weight(.semibold))

                    Text("Browse any site with media support")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                if viewModel.isMediaActive {
                    mediaBanner
                }

                if !viewModel.bookmarks.isEmpty {
                    bookmarksGrid
                }

                quickLinks
            }
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var mediaBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Active")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    if viewModel.hasFrontSource {
                        Label("Front", systemImage: "person.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                    if viewModel.hasBackSource {
                        Label("Back", systemImage: "arrow.triangle.capsulepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.green.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private var bookmarksGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bookmarks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 72), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.bookmarks.prefix(8)) { bookmark in
                    Button {
                        viewModel.urlText = bookmark.urlString
                        viewModel.navigateTo(bookmark.urlString)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(width: 56, height: 56)
                                Text(String(bookmark.title.prefix(2)).uppercased())
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Text(bookmark.displayHost)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 72)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Links")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                quickLinkRow(icon: "video.badge.checkmark", title: "Webcam Test", subtitle: "webcamtests.com", url: "https://webcamtests.com/check", tint: .green)
                Divider().padding(.leading, 52)
                quickLinkRow(icon: "checkmark.shield.fill", title: "Liveness Check", subtitle: "kyctest.rork.app", url: "https://kyctest.rork.app", tint: .blue)
                Divider().padding(.leading, 52)
                quickLinkRow(icon: "bubble.left.and.bubble.right.fill", title: "Discord", subtitle: "discord.com", url: "https://discord.com", tint: .indigo)
                Divider().padding(.leading, 52)
                quickLinkRow(icon: "play.rectangle.fill", title: "YouTube", subtitle: "youtube.com", url: "https://youtube.com", tint: .red)
                Divider().padding(.leading, 52)
                quickLinkRow(icon: "gamecontroller.fill", title: "Twitch", subtitle: "twitch.tv", url: "https://twitch.tv", tint: .purple)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func quickLinkRow(icon: String, title: String, subtitle: String, url: String, tint: Color = .accentColor) -> some View {
        Button {
            viewModel.urlText = url
            viewModel.navigateTo(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var overlayLayer: some View {
        Group {
            if let image = viewModel.sourceImage, viewModel.sourceType == .image {
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                    .clipped()
                    .opacity(viewModel.overlayOpacity)
            } else if let videoURL = viewModel.sourceVideoURL {
                LoopingVideoPlayer(url: videoURL)
                    .opacity(viewModel.overlayOpacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Button {
                if viewModel.canGoBack {
                    viewModel.goBack()
                } else {
                    viewModel.goHome()
                }
            } label: {
                toolbarIcon("chevron.backward")
            }
            .disabled(viewModel.currentURL == nil)

            Spacer()

            Button { viewModel.goForward() } label: {
                toolbarIcon("chevron.forward")
            }
            .disabled(!viewModel.canGoForward)

            Spacer()

            Button { viewModel.showOverlayPanel = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.isMediaActive ? "web.camera.fill" : "web.camera")
                        .font(.system(size: 18))
                        .foregroundStyle(viewModel.isMediaActive ? Color.green : .primary)
                        .frame(width: 44, height: 44)

                    if viewModel.isMediaActive {
                        HStack(spacing: 2) {
                            if viewModel.hasFrontSource {
                                Circle().fill(.cyan).frame(width: 6, height: 6)
                            }
                            if viewModel.hasBackSource {
                                Circle().fill(.green).frame(width: 6, height: 6)
                            }
                        }
                        .offset(x: -4, y: 8)
                    }
                }
            }

            Spacer()

            Button {
                viewModel.addBookmark()
            } label: {
                toolbarIcon(viewModel.isCurrentPageBookmarked() ? "bookmark.fill" : "bookmark")
            }
            .disabled(viewModel.currentURL == nil)

            Spacer()

            Button { viewModel.showBookmarks = true } label: {
                toolbarIcon("book")
            }

            Spacer()

            Button { viewModel.showDownloads = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: viewModel.downloadService.hasActiveDownload ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(viewModel.downloadService.hasActiveDownload ? Color.accentColor : Color.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .accessibilityLabel("Downloads")

            Spacer()

            Button { viewModel.showBurnConfirmation = true } label: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(.bar)
    }

    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
    }
}
