import Foundation
import SwiftData

// Versioned from day one so later changes can migrate cleanly.
enum HistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PlaylistHistoryEntry.self, HistoryTrack.self]
    }

    /// One generated playlist, kept whether or not it was saved to Apple Music.
    @Model
    final class PlaylistHistoryEntry {
        #Index<PlaylistHistoryEntry>([\.createdAt], [\.isFavorite])

        var createdAt: Date
        var updatedAt: Date
        var name: String
        /// Searchable text: the theme, or "Inspired by <seed>".
        var promptSummary: String
        /// JSON-encoded `PlaylistPrompt`, used to refine or regenerate later.
        var promptData: Data
        var refinements: [String]
        var providerName: String
        var isFavorite: Bool
        var trackCount: Int
        var matchedCount: Int
        var savedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \HistoryTrack.entry)
        var tracks: [HistoryTrack] = []

        init(name: String, promptSummary: String, promptData: Data, providerName: String) {
            let now = Date.now
            self.createdAt = now
            self.updatedAt = now
            self.name = name
            self.promptSummary = promptSummary
            self.promptData = promptData
            self.refinements = []
            self.providerName = providerName
            self.isFavorite = false
            self.trackCount = 0
            self.matchedCount = 0
        }

        var prompt: PlaylistPrompt? {
            try? JSONDecoder().decode(PlaylistPrompt.self, from: promptData)
        }

        /// Relationship arrays are unordered, so keep an explicit position.
        var orderedTracks: [HistoryTrack] {
            tracks.sorted { $0.position < $1.position }
        }
    }

    @Model
    final class HistoryTrack {
        enum Status: String, Codable {
            case found
            case notFound
            /// Never confirmed either way (search failed or was interrupted).
            case unchecked
        }

        var position: Int
        var title: String
        var artist: String
        var album: String
        var genre: String
        var reason: String
        /// Apple Music catalog ID when matched, so it can be re-fetched without searching.
        var catalogID: String?
        var status: Status
        var entry: PlaylistHistoryEntry?

        init(position: Int, item: SongItem, catalogID: String?, status: Status) {
            self.position = position
            self.title = item.title
            self.artist = item.artist
            self.album = item.album
            self.genre = item.genre
            self.reason = item.reason
            self.catalogID = catalogID
            self.status = status
        }

        var item: SongItem {
            SongItem(title: title, artist: artist, album: album, genre: genre, reason: reason)
        }
    }
}

enum HistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [HistorySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias PlaylistHistoryEntry = HistorySchemaV1.PlaylistHistoryEntry
typealias HistoryTrack = HistorySchemaV1.HistoryTrack
