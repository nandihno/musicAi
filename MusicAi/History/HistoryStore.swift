import Foundation
import MusicKit
import OSLog
import SwiftData

/// What the generator hands over to be remembered.
struct HistorySnapshot {
    var name: String
    var prompt: PlaylistPrompt
    var refinements: [String]
    var providerName: String
    var tracks: [GeneratedTrack]
    var savedAt: Date?
}

/// Writes generator sessions into SwiftData. Lives on the main actor with the
/// view's `modelContext`; model objects never leave it.
final class HistoryStore {
    private let context: ModelContext
    private let logger = Logger(subsystem: "org.nando.MusicAi", category: "History")

    init(context: ModelContext) {
        self.context = context
    }

    /// Creates or updates an entry and returns its (saved, permanent) identifier.
    @discardableResult
    func upsert(id: PersistentIdentifier?, snapshot: HistorySnapshot) -> PersistentIdentifier? {
        guard let promptData = try? JSONEncoder().encode(snapshot.prompt) else { return id }

        let entry: PlaylistHistoryEntry
        if let id, let existing = self.entry(for: id) {
            entry = existing
        } else {
            entry = PlaylistHistoryEntry(
                name: snapshot.name,
                promptSummary: snapshot.prompt.summary,
                promptData: promptData,
                providerName: snapshot.providerName
            )
            context.insert(entry)
        }

        entry.updatedAt = .now
        entry.name = snapshot.name
        entry.promptData = promptData
        entry.refinements = snapshot.refinements
        entry.providerName = snapshot.providerName
        entry.trackCount = snapshot.tracks.count
        entry.matchedCount = snapshot.tracks.filter { $0.song != nil }.count
        if let savedAt = snapshot.savedAt {
            entry.savedAt = savedAt
        }

        for track in entry.tracks {
            context.delete(track)
        }
        entry.tracks = snapshot.tracks.enumerated().map { position, track in
            HistoryTrack(
                position: position,
                item: track.item,
                catalogID: track.song?.id.rawValue,
                status: Self.status(for: track.match)
            )
        }

        do {
            try context.save()
        } catch {
            // History is a convenience; never let it break generating or saving.
            logger.error("Couldn't save history: \(error.localizedDescription)")
        }
        return entry.persistentModelID
    }

    func entry(for id: PersistentIdentifier) -> PlaylistHistoryEntry? {
        var descriptor = FetchDescriptor<PlaylistHistoryEntry>(
            predicate: #Predicate { $0.persistentModelID == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func status(for match: GeneratedTrack.Match) -> HistoryTrack.Status {
        switch match {
        case .found: .found
        case .notFound: .notFound
        case .searching, .replacing, .searchFailed: .unchecked
        }
    }
}
