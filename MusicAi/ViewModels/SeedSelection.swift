import Foundation
import MusicKit
import Observation

/// The songs picked on the Mash Up tab. Shared by the playlist, search, and
/// Now Playing screens so a selection survives navigating between them.
@Observable
final class SeedSelection {
    static let maxSeeds = 5

    enum AddResult: Equatable {
        case added
        case alreadyAdded
        case full
    }

    private(set) var songs: [Song] = []

    var isEmpty: Bool { songs.isEmpty }
    var isFull: Bool { songs.count >= Self.maxSeeds }

    func contains(_ song: Song) -> Bool {
        songs.contains { $0.id == song.id }
    }

    @discardableResult
    func add(_ song: Song) -> AddResult {
        if contains(song) { return .alreadyAdded }
        guard !isFull else { return .full }
        songs.append(song)
        return .added
    }

    func toggle(_ song: Song) {
        if contains(song) {
            remove(song)
        } else {
            add(song)
        }
    }

    func remove(_ song: Song) {
        songs.removeAll { $0.id == song.id }
    }

    func clear() {
        songs = []
    }

    /// One seed keeps the single-song prompt; two or more are blended.
    var prompt: PlaylistPrompt? {
        switch songs.count {
        case 0: nil
        case 1: .seed(SongMetadata(from: songs[0]))
        default: .blend(songs.map(SongMetadata.init(from:)))
        }
    }

    // MARK: - Now Playing

    enum NowPlayingError: LocalizedError {
        case nothingPlaying
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .nothingPlaying:
                "Nothing is playing in the Music app right now."
            case .notFound(let title):
                "Couldn't find \u{201C}\(title)\u{201D} on Apple Music."
            }
        }
    }

    /// Adds the song currently playing in the Music app. The system player doesn't
    /// always expose the song itself, so fall back to a catalog search on title and artist.
    func addNowPlaying() async throws -> (Song, AddResult) {
        let status = MusicAuthorization.currentStatus == .authorized
            ? .authorized
            : await MusicAuthorization.request()
        guard status == .authorized else { throw MusicKitService.MusicKitError.notAuthorized }

        guard let entry = SystemMusicPlayer.shared.queue.currentEntry else {
            throw NowPlayingError.nothingPlaying
        }

        let song: Song
        if case .song(let playing) = entry.item {
            song = playing
        } else if let artist = entry.subtitle,
                  let match = try await MusicKitService.findCatalogSong(title: entry.title, artist: artist) {
            song = match
        } else {
            throw NowPlayingError.notFound(entry.title)
        }

        return (song, add(song))
    }
}
