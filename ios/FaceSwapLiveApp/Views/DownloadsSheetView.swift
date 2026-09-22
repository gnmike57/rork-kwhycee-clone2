import QuickLook
import SwiftUI

/// Full-height sheet listing every browser download with open, share, and
/// delete actions — plus Quick Look and share helpers used by its rows.
struct DownloadsSheetView: View {
    @Bindable var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var previewFile: PresentedFile?
    @State private var shareFile: PresentedFile?
    @State private var deleteCandidate: DownloadItem?

    private var service: DownloadService { viewModel.downloadService }

    var body: some View {
        NavigationStack {
            Group {
                if service.downloads.isEmpty {
                    emptyState
                } else {
                    downloadList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $deleteCandidate) { item in
            DeleteConfirmationDialog(item: item) {
                service.delete(itemID: item.id)
            }
        }
        .sheet(item: $previewFile) { file in
            QuickLookPreview(url: file.url)
                .ignoresSafeArea(.all, edges: .bottom)
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    private var downloadList: some View {
        List {
            ForEach(service.downloads) { item in
                DownloadRow(
                    item: item,
                    onOpen: {
                        if item.state == .completed {
                            previewFile = PresentedFile(url: service.fileURL(for: item.fileName))
                        }
                    },
                    onShare: {
                        if item.state == .completed {
                            shareFile = PresentedFile(url: service.fileURL(for: item.fileName))
                        }
                    },
                    onRetry: { service.retry(itemID: item.id) },
                    onCancel: { service.cancel(itemID: item.id) },
                    onDelete: { deleteCandidate = item }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableViewCompat(
            icon: "arrow.down.circle",
            title: "No Downloads Yet",
            message: "Files you download in the browser will appear here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sheet payload: `URL` is not `Identifiable`, so presentations key on this.
private struct PresentedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Row

private struct DownloadRow: View {
    let item: DownloadItem
    var onOpen: () -> Void
    var onShare: () -> Void
    var onRetry: () -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                detailLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture {
            if item.state == .completed { onOpen() }
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 40)
            Image(systemName: item.symbolName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        switch item.state {
        case .downloading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(sizeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Text("\(dateText) · \(sizeCaption)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(item.errorText ?? "Download failed")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private var sizeCaption: String {
        if let total = item.totalBytes, total > 0 {
            return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
        if let received = item.receivedBytes, received > 0 {
            return ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        }
        return "—"
    }

    private var dateText: String {
        item.finishedAt.map { date in
            date.formatted(date: .abbreviated, time: .shortened)
        } ?? ""
    }

    @ViewBuilder
    private var actions: some View {
        switch item.state {
        case .downloading:
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .completed:
            HStack(spacing: 4) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share \(item.fileName)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(item.fileName)")
            }
        case .failed:
            HStack(spacing: 4) {
                Button("Retry", action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(item.fileName)")
            }
        }
    }
}

// MARK: - Delete confirmation

/// Presented with `.sheet(item:)` so each download's delete ask is keyed by
/// the record, not by shared state.
private struct DeleteConfirmationDialog: View {
    let item: DownloadItem
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Delete “\(item.fileName)”?")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("The file will be removed from Downloads. This cannot be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(role: .destructive, action: {
                onConfirm()
                dismiss()
            }) {
                Text("Delete")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") { dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Empty state

/// Small stand-in so the sheet does not depend on iOS 17-only
/// ContentUnavailableView styling decisions.
private struct ContentUnavailableViewCompat: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

// MARK: - Quick Look

/// Opens a downloaded file in place with the system preview.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
