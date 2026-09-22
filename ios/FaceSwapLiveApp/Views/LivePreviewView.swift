import SwiftUI
import PhotosUI

struct LivePreviewView: View {
    @State private var viewModel = PreviewViewModel()

    var body: some View {
        ZStack {
            previewLayer
                .ignoresSafeArea()

            if viewModel.showCaptureFlash {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()

                if !viewModel.isActive && !viewModel.isProcessingSource {
                    selectPrompt
                        .padding(.bottom, 32)
                        .transition(.scale.combined(with: .opacity))
                }

                if viewModel.isProcessingSource {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                        .padding(.bottom, 32)
                }

                bottomBar
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showCaptureFlash)
        .statusBarHidden()
        .sheet(isPresented: $viewModel.showImageSelection) {
            ImageSelectionSheet { image in
                viewModel.selectSourceImage(image)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $viewModel.showGallery) {
            GalleryView(images: viewModel.capturedImages)
        }
        .alert("No Face Detected", isPresented: $viewModel.showNoResultAlert) {
            Button("OK") {}
        } message: {
            Text("No face was found in the selected photo. Please try a different photo with a clear, front-facing face.")
        }
        .onAppear {
            viewModel.startCapture()
        }
        .onDisappear {
            viewModel.stopCapture()
        }
    }

    private var previewLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                MediaPreviewView(frame: viewModel.previewFrame) { rotation in
                    viewModel.setRotation(rotation)
                }

                if let overlay = viewModel.overlayImage,
                   viewModel.isActive,
                   viewModel.detectedRect.width > 0 {
                    overlayView(overlay)
                }

                if viewModel.showDebugOverlay, viewModel.detectedRect.width > 0 {
                    debugOverlayCanvas
                }

                cameraStateOverlay
            }
            .onAppear { viewModel.viewSize = geo.size }
            .onChange(of: geo.size) { _, size in viewModel.viewSize = size }
        }
    }

    /// What stands in for the picture while the camera is not delivering:
    /// a spinner while it starts, and a plain explanation when it cannot run.
    @ViewBuilder
    private var cameraStateOverlay: some View {
        switch viewModel.availability {
        case .running:
            EmptyView()
        case .idle, .starting:
            if viewModel.previewFrame == nil {
                ProgressView()
                    .tint(.white)
                    .transition(.opacity)
            }
        case .permissionDenied:
            CameraUnavailableView(
                symbol: "video.slash.fill",
                title: "Camera Access Is Off",
                message: "Allow camera access in Settings to use the live preview.",
                action: ("Open Settings", openSettings)
            )
        case .noCamera:
            CameraUnavailableView(
                symbol: "camera.metering.unknown",
                title: "No Camera Found",
                message: "This device has no camera available to the app.",
                action: nil
            )
        case .failed(let reason):
            CameraUnavailableView(
                symbol: "exclamationmark.triangle.fill",
                title: "Camera Unavailable",
                message: reason,
                action: ("Try Again", { viewModel.startCapture() })
            )
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func overlayView(_ overlay: UIImage) -> some View {
        let rect = viewModel.detectedRect
        let expandedWidth = rect.width * 1.8
        let expandedHeight = expandedWidth / viewModel.sourceAspectRatio

        return Image(uiImage: overlay)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: expandedWidth, height: expandedHeight)
            .rotationEffect(.radians(viewModel.roll))
            .position(x: rect.midX, y: rect.midY - rect.height * 0.03)
            .opacity(0.88)
            .allowsHitTesting(false)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: rect)
    }

    private var debugOverlayCanvas: some View {
        Canvas { context, _ in
            let rect = viewModel.detectedRect
            let rectPath = Path { p in
                p.addRect(rect)
            }
            context.stroke(rectPath, with: .color(.green), lineWidth: 3)

            for point in viewModel.debugLandmarkScreenPoints {
                let dotPath = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.fill(dotPath, with: .color(.red))
            }
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            if viewModel.isActive {
                Button { viewModel.clearSelection() } label: {
                    Image(systemName: "xmark")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Button {
                viewModel.showDebugOverlay.toggle()
            } label: {
                Image(systemName: viewModel.showDebugOverlay ? "eye.fill" : "eye.slash")
                    .font(.callout.bold())
                    .foregroundStyle(viewModel.showDebugOverlay ? .yellow : .white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button { viewModel.switchPosition() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .animation(.spring(duration: 0.25), value: viewModel.isActive)
    }

    private var selectPrompt: some View {
        Button { viewModel.showImageSelection = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .symbolEffect(.bounce.byLayer, options: .repeating.speed(0.4))
                Text("Select an Image")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            Button { viewModel.showImageSelection = true } label: {
                if let overlay = viewModel.overlayImage {
                    Image(uiImage: overlay)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))
                } else {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 50, height: 50)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: 60)

            Spacer()

            Button { viewModel.capture() } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 74, height: 74)
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                }
            }
            .buttonStyle(CaptureButtonStyle())
            .disabled(!viewModel.isCameraRunning)
            .opacity(viewModel.isCameraRunning ? 1 : 0.4)
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.showCaptureFlash)

            Spacer()

            Button { viewModel.showGallery = true } label: {
                if let lastCapture = viewModel.capturedImages.first {
                    Image(uiImage: lastCapture.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.4), lineWidth: 2)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                            .frame(width: 50, height: 50)
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}

/// A plain explanation for a camera that cannot run, with one way forward.
private struct CameraUnavailableView: View {
    let symbol: String
    let title: String
    let message: String
    let action: (label: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 96, height: 96)
                .background(.white.opacity(0.06), in: Circle())

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let action {
                Button(action.label, action: action.perform)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}
