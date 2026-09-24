import Foundation

/// A song suggested by the AI, before it has been matched against the Apple Music catalog.
nonisolated struct SongItem: Codable, Hashable, Sendable {
    let title: String
    let artist: String
    let album: String
    let genre: String
    let reason: String

    /// Title + artist normalized so "Song (feat. X)" and "song" count as the same track.
    var dedupeKey: String {
        "\(MusicKitService.normalized(title))|\(MusicKitService.normalized(artist))"
    }
}
