import SwiftUI
import SwiftData

/// Reopens a past playlist in the same review UI, so it can be edited, refined,
/// or saved (again). Changes are written back to the same History entry.
struct HistoryDetailView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Bindable var entry: PlaylistHistoryEntry

    @State private var generator = PlaylistGenerator()
    @State private var previewPlayer = PreviewPlayer()
    @State private var didRestore = false

    var body: some View {
        List {
            headerCard
                .cardRow()
            GenerationFeedbackRows(generator: generator)
            GeneratedPlaylistSection(generator: generator, previewPlayer: previewPlayer)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    entry.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                }
                .tint(.yellow)
                .accessibilityLabel(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            if generator.canEdit {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
        .generatorFeedback(generator)
        .task {
            guard !didRestore else { return }
            didRestore = true
            generator.attachHistory(modelContext)
            generator.restore(entry, provider: settings.provider)
        }
        .onDisappear {
            generator.cancel()
            previewPlayer.stop()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.promptSummary)
                .font(.headline)
            Text("\(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) \u{00B7} \(entry.providerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.prompt == nil {
                Label("This entry can't be refined because its prompt couldn't be read.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
