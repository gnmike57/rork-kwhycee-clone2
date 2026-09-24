import SwiftUI
import AVFoundation

struct DiagnosticsView: View {
    @Environment(DeviceProfileManager.self) private var profileManager
    @State private var diagnosticsService = DiagnosticsService()
    @State private var fingerprintService = FingerprintService()
    @State private var constraintLog = ConstraintLogService()
    @State private var siteHistory = SiteHistoryService()
    @State private var exportService = ExportBundleService()
    @State private var mediaReport: MediaMetadataReport?
    @State private var conformanceScore: MediaConformanceScore?
    @State private var showFilePicker = false

    @State private var expandedSections: Set<String> = ["session"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sessionDiagnosticsSection
                    if LivingStills.isAvailable {
                        faceTrackingSection
                    }
                    cameraComparisonSection
                    fingerprintSection
                    metadataInspectorSection
                    audioRouteSection
                    driftMonitorSection
                    constraintLogSection
                    siteHistorySection
                    exportBundleSection
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Diagnostics")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Session Diagnostics

    private var sessionDiagnosticsSection: some View {
        sectionCard("Session Diagnostics", icon: "waveform.badge.magnifyingglass", sectionID: "session") {
            if let diag = diagnosticsService.liveDiagnostics {
                VStack(spacing: 8) {
                    diagRow("Resolution", "\(diag.activeWidth)×\(diag.activeHeight)")
                    diagRow("Aspect Ratio", diag.aspectRatio)
                    diagRow("FPS", String(format: "%.1f", diag.fps))
                    diagRow("Color Space", diag.colorSpace)
                    diagRow("Orientation", diag.orientation)
                    diagRow("Mirrored", diag.isMirrored.map { $0 ? "Yes" : "No" } ?? "Not measured")
                    diagRow("HDR", diag.isHDR ? "Enabled" : "Disabled")
                    diagRow("Stabilization", diag.stabilizationMode)
                }
            } else {
                ContentUnavailableView {
                    Label("No Active Session", systemImage: "video.slash")
                        .font(.subheadline)
                } description: {
                    Text("Start a live preview to capture session diagnostics.")
                        .font(.caption)
                }
                .frame(height: 100)
            }
        }
    }

    // MARK: - Face Tracking (Stage 1 dev surface)

    private var faceTrackingSection: some View {
        sectionCard("Face Tracking", icon: "face.smiling", sectionID: "face") {
            FaceTrackingDevSection()
        }
    }

    // MARK: - Camera Comparison

    private var cameraComparisonSection: some View {
        sectionCard("Camera Comparison", icon: "camera.on.rectangle", sectionID: "camera") {
            if let profile = profileManager.activeProfile,
               let front = profile.frontCamera,
               let back = profile.backCamera {
                VStack(spacing: 0) {
                    comparisonHeader
                    Divider().padding(.vertical, 6)
                    comparisonRow("Resolution", "\(front.activeWidth)×\(front.activeHeight)", "\(back.activeWidth)×\(back.activeHeight)")
                    comparisonRow("Frame Rate", "\(Int(front.activeFrameRate)) fps", "\(Int(back.activeFrameRate)) fps")
                    comparisonRow("Codec", front.testClipCodec ?? "—", back.testClipCodec ?? "—")
                    comparisonRow("Bitrate", formatBitrate(front.testClipBitrate), formatBitrate(back.testClipBitrate))
                    comparisonRow("Color Space", front.activeColorSpace ?? "—", back.activeColorSpace ?? "—")
                    if let frontFOV = front.supportedFormats.first?.videoFieldOfView,
                       let backFOV = back.supportedFormats.first?.videoFieldOfView {
                        comparisonRow("FOV", String(format: "%.0f°", frontFOV), String(format: "%.0f°", backFOV))
                    }
                }
            } else {
                Text("Requires a profile with front and back cameras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    private var comparisonHeader: some View {
        HStack {
            Text("")
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text("Front")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            Spacer()
            Text("Back")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        }
    }

    private func comparisonRow(_ label: String, _ frontVal: String, _ backVal: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(frontVal)
                .font(.caption)
                .foregroundStyle(.cyan)
                .frame(maxWidth: .infinity)
            Spacer()
            Text(backVal)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Fingerprint Consistency

    private var fingerprintSection: some View {
        sectionCard("Fingerprint Consistency", icon: "fingerprint", sectionID: "fingerprint") {
            VStack(spacing: 10) {
                if let passed = fingerprintService.testPassed {
                    HStack(spacing: 8) {
                        Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(passed ? .green : .red)
                        Text(passed ? "All Consistent" : "Inconsistencies Found")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(passed ? .green : .red)
                        Spacer()
                    }
                    .padding(10)
                    .background((passed ? Color.green : Color.red).opacity(0.1), in: .rect(cornerRadius: 8))
                }

                if !fingerprintService.consistencyResults.isEmpty {
                    ForEach(fingerprintService.consistencyResults) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.isConsistent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isConsistent ? .green : .red)
                                .font(.caption)
                            Text(result.field)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(result.values.prefix(3).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                NavigationLink {
                    FingerprintConsistencyView(service: fingerprintService)
                } label: {
                    Label("Open Consistency Test", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.cyan.opacity(0.15), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - Metadata Inspector

    private var metadataInspectorSection: some View {
        sectionCard("Metadata Inspector", icon: "doc.text.magnifyingglass", sectionID: "metadata") {
            VStack(spacing: 10) {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Select Media File", systemImage: "folder.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.purple.opacity(0.15), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.purple)
                }

                if let report = mediaReport {
                    VStack(spacing: 6) {
                        diagRow("Container", report.container)
                        diagRow("Video Codec", report.videoCodec)
                        diagRow("Resolution", "\(report.videoWidth)×\(report.videoHeight)")
                        diagRow("Bitrate", formatBitrate(report.videoBitrate))
                        diagRow("Frame Rate", String(format: "%.1f fps", report.videoFrameRate))
                        diagRow("Pixel Format", report.pixelFormat)
                        diagRow("Rotation", "\(report.rotationDegrees)°")
                        diagRow("HDR", report.isHDR ? "Yes" : "No")
                        diagRow("Color", "\(report.colorPrimaries) / \(report.transferFunction)")

                        if report.hasAudio {
                            Divider().padding(.vertical, 2)
                            diagRow("Audio Codec", report.audioCodec)
                            diagRow("Audio Bitrate", formatBitrate(report.audioBitrate))
                            diagRow("Sample Rate", "\(Int(report.audioSampleRate)) Hz")
                            diagRow("Channels", "\(report.audioChannels)")
                        }
                    }

                    if let score = conformanceScore {
                        VStack(spacing: 6) {
                            Divider().padding(.vertical, 2)
                            HStack {
                                Text("Conformance")
                                    .font(.caption.weight(.bold))
                                Spacer()
                                Text(String(format: "%.0f%%", score.overallScore))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(score.overallScore >= 80 ? .green : score.overallScore >= 50 ? .yellow : .red)
                            }
                            conformanceField("Resolution", score.resolutionMatch)
                            conformanceField("FPS", score.fpsMatch)
                            conformanceField("Codec", score.codecMatch)
                            conformanceField("Bitrate", score.bitrateMatch)
                            conformanceField("Orientation", score.orientationMatch)
                            conformanceField("Audio", score.audioMatch)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.movie, .video, .quickTimeMovie]) { result in
                mediaReport = nil
                conformanceScore = nil
                if case .success(let url) = result {
                    Task {
                        mediaReport = await DiagnosticsService.inspectMediaFile(at: url)
                        if let report = mediaReport,
                           let camera = profileManager.activeProfile?.frontCamera {
                            conformanceScore = DiagnosticsService.scoreConformance(media: report, camera: camera)
                        }
                    }
                }
            }
        }
    }

    private func conformanceField(_ label: String, _ passed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
                .font(.caption2)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Audio Route

    private var audioRouteSection: some View {
        sectionCard("Audio Route", icon: "speaker.wave.2.fill", sectionID: "audio") {
            VStack(spacing: 10) {
                if let route = diagnosticsService.audioRouteProfile {
                    diagRow("Input", route.inputRoute)
                    diagRow("Sample Rate", "\(Int(route.sampleRate)) Hz")
                    diagRow("Channels", "\(route.channelCount)")
                    diagRow("Bit Depth", route.bitDepth.map { "\($0)" } ?? "Not measured")
                    diagRow("Echo Cancel", route.echoCancellation ? "On" : "Off")
                    diagRow("Mode", route.audioSessionMode)
                    diagRow("Buffer", String(format: "%.3f s", route.ioBufferDuration))
                }

                Button {
                    diagnosticsService.captureAudioRouteProfile()
                } label: {
                    Label("Capture Audio Route", systemImage: "mic.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.cyan.opacity(0.15), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - Drift Monitor

    private var driftMonitorSection: some View {
        sectionCard("Drift Monitor", icon: "chart.xyaxis.line", sectionID: "drift") {
            VStack(spacing: 10) {
                if let report = diagnosticsService.driftReport {
                    diagRow("Average FPS", String(format: "%.2f", report.averageFPS))
                    diagRow("Jitter Frames", "\(report.jitterCount)")
                    diagRow("Duplicates", "\(report.duplicateCount)")
                    diagRow("Total Frames", "\(report.totalFrames)")
                    diagRow("Min Delta", String(format: "%.4f s", report.minDelta))
                    diagRow("Max Delta", String(format: "%.4f s", report.maxDelta))
                }

                Button {
                    diagnosticsService.generateDriftReport()
                } label: {
                    Label("Analyze Frame Timing", systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.cyan.opacity(0.15), in: .rect(cornerRadius: 10))
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - Constraint Log

    private var constraintLogSection: some View {
        sectionCard("Constraint Log", icon: "list.clipboard", sectionID: "constraints") {
            VStack(spacing: 10) {
                if constraintLog.entries.isEmpty {
                    Text("No constraint entries logged yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(constraintLog.entries.prefix(5)) { entry in
                        constraintEntryRow(entry)
                    }

                    NavigationLink {
                        ConstraintLogView(constraintLog: constraintLog)
                    } label: {
                        Text("View All (\(constraintLog.entries.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity)
                    }

                    Button(role: .destructive) {
                        constraintLog.clearLog()
                    } label: {
                        Label("Clear Log", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func constraintEntryRow(_ entry: ConstraintLogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.wasSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.wasSuccessful ? .green : .red)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.siteURL)
                    .font(.caption)
                    .lineLimit(1)
                Text(entry.requestedConstraints.prefix(60))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(entry.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Site History

    private var siteHistorySection: some View {
        sectionCard("Site History", icon: "clock.arrow.circlepath", sectionID: "sites") {
            VStack(spacing: 10) {
                let sites = siteHistory.uniqueSites()
                if sites.isEmpty {
                    Text("No site history recorded yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    ForEach(sites.prefix(5), id: \.self) { site in
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .foregroundStyle(.cyan)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site)
                                    .font(.caption)
                                    .lineLimit(1)
                                if let profile = siteHistory.lastSuccessfulProfile(for: site) {
                                    Text("Last: \(profile)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    NavigationLink {
                        SiteHistoryView(siteHistory: siteHistory)
                    } label: {
                        Text("View All (\(sites.count) sites)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity)
                    }

                    Button(role: .destructive) {
                        siteHistory.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Export Bundle

    private var exportBundleSection: some View {
        sectionCard("Export Debug Bundle", icon: "square.and.arrow.up", sectionID: "export") {
            VStack(spacing: 10) {
                Button {
                    Task {
                        await exportService.exportBundle(
                            profile: profileManager.activeProfile,
                            constraintLogs: constraintLog.entries,
                            siteHistory: siteHistory.entries,
                            sessionDiagnostics: exportJSON(diagnosticsService.liveDiagnostics),
                            mediaMetadata: exportJSON(mediaReport),
                            fingerprintResults: exportJSON(fingerprintService.consistencyResults)
                        )
                    }
                } label: {
                    if exportService.isExporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    } else {
                        Label("Export Bundle", systemImage: "doc.zipper")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.cyan, in: .rect(cornerRadius: 10))
                            .foregroundStyle(.black)
                    }
                }
                .disabled(exportService.isExporting)

                if let url = exportService.lastExportURL {
                    ShareLink(item: url) {
                        Label("Share Last Bundle", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(
        _ title: String,
        icon: String,
        sectionID: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    if expandedSections.contains(sectionID) {
                        expandedSections.remove(sectionID)
                    } else {
                        expandedSections.insert(sectionID)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.cyan)
                        .frame(width: 24)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expandedSections.contains(sectionID) ? 180 : 0))
                }
                .padding(14)
            }

            if expandedSections.contains(sectionID) {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func formatBitrate(_ bitrate: Int?) -> String {
        guard let br = bitrate, br > 0 else { return "—" }
        if br >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(br) / 1_000_000)
        }
        return "\(br / 1000) kbps"
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        formatBitrate(Optional(bitrate))
    }

    /// Pretty-printed JSON for the debug bundle, so the exported sections carry
    /// whatever the screen is actually showing.
    private func exportJSON<T: Encodable>(_ value: T?) -> String {
        guard let value else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
