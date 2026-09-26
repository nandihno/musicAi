import SwiftUI
import SwiftData

struct HistoryView: View {
    @State private var searchText = ""
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            HistoryList(searchText: searchText, favoritesOnly: favoritesOnly)
                .appBackground()
                .navigationTitle("History")
                .searchable(text: $searchText, prompt: "Search playlists")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Toggle(isOn: $favoritesOnly) {
                            Label("Favorites Only", systemImage: favoritesOnly ? "star.fill" : "star")
                        }
                        .toggleStyle(.button)
                        .tint(.yellow)
                    }
                }
                .settingsToolbar()
                .navigationDestination(for: PlaylistHistoryEntry.self) { entry in
                    HistoryDetailView(entry: entry)
                }
        }
    }
}

// MARK: - List

/// Owns the `@Query` so the filter can be rebuilt from the search text.
private struct HistoryList: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [PlaylistHistoryEntry]

    private let isFiltering: Bool

    init(searchText: String, favoritesOnly: Bool) {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        isFiltering = !search.isEmpty || favoritesOnly
        _entries = Query(
            filter: #Predicate<PlaylistHistoryEntry> { entry in
                (!favoritesOnly || entry.isFavorite) &&
                (search.isEmpty ||
                    entry.name.localizedStandardContains(search) ||
                    entry.promptSummary.localizedStandardContains(search))
            },
            sort: \PlaylistHistoryEntry.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        if entries.isEmpty {
            if isFiltering {
                ContentUnavailableView.search
            } else {
                ContentUnavailableView(
                    "No Playlists Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Playlists you generate appear here, even if you haven't saved them to Apple Music.")
                )
            }
        } else {
            List {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) {
                        HistoryRow(entry: entry)
                    }
                    .listRowBackground(Theme.gradientStart.opacity(0.06))
                    .swipeActions(edge: .leading) {
                        Button {
                            entry.isFavorite.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(
                                entry.isFavorite ? "Unfavorite" : "Favorite",
                                systemImage: entry.isFavorite ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: PlaylistHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                Spacer()
                if entry.savedAt != nil {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            // Theme playlists are named after the prompt, so skip the repeat.
            if !entry.name.localizedCaseInsensitiveContains(entry.promptSummary) {
                Text(entry.promptSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts = [
            "\(entry.matchedCount)/\(entry.trackCount) on Apple Music",
            entry.providerName,
            entry.createdAt.formatted(.relative(presentation: .named))
        ]
        if !entry.refinements.isEmpty {
            parts.insert("refined \(entry.refinements.count)\u{00D7}", at: 1)
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
