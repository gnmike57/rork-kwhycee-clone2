import SwiftUI

/// Dismissible asked-vs-sent timeline after injection turns off.
struct SequenceRecapView: View {
    let recap: SequenceRecap
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(recap.events) { event in
                        eventRow(event)
                    }
                    if recap.events.isEmpty {
                        Text("No requests were recorded on this visit.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
                .padding(16)
            }
            .background(MediaTheme.canvas)
            .navigationTitle("Sequence recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(MediaTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MediaTheme.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recap.host.isEmpty ? "This page" : recap.host)
                .font(.headline)
            Text(recap.endedBecause)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(timeRange)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MediaTheme.card, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: recap.startedAt)) – \(formatter.string(from: recap.endedAt))"
    }

    private func eventRow(_ event: RecapEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.kind == .live ? "Camera" : "File")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MediaTheme.accent)
                Spacer()
                Text(event.time, style: .time)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            comparison("Camera", event.askedFacing, event.sentFacing)
            comparison("Size", event.askedSize, event.sentSize)
            if event.kind == .live {
                comparison("Frame rate", event.askedFrameRate, event.sentFrameRate)
                if event.wantsAudio {
                    comparison("Sound", "Requested", "Silent track")
                }
            }
            if let crop = event.cropPercent {
                Text("Crop \(crop)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !event.note.isEmpty {
                Text(event.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(MediaTheme.card, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MediaTheme.stroke, lineWidth: 1)
        )
    }

    private func comparison(_ label: String, _ asked: String, _ sent: String) -> some View {
        let differs = asked.lowercased() != sent.lowercased()
            && asked != "Unspecified"
            && asked != "Any size"
            && asked != "Any rate"
            && asked != "—"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(asked)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(sent)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(differs ? Color.orange : .primary)
        }
    }
}
