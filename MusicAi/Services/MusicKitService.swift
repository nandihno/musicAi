import Foundation
import MusicKit

actor MusicKitService {
    enum MusicKitError: LocalizedError {
        case notAuthorized
        case playlistCreationFailed(String)
        case syncLibraryOff

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "Music access not authorized. Please allow access in Settings."
            case .playlistCreationFailed(let detail):
                "Failed to create playlist: \(detail)"
            case .syncLibraryOff:
                "Turn on Sync Library in Settings \u{203A} Apps \u{203A} Music to save playlists."
            }
        }

        var isRetryable: Bool {
            if case .playlistCreationFailed = self { true } else { false }
        }
    }

    enum LibraryAccess {
        case available
        case needsSubscription
        case needsSyncLibrary
    }

    func requestAuthorization() async throws {
        if MusicAuthorization.currentStatus == .authorized { return }
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            throw MusicKitError.notAuthorized
        }
    }

    func createPlaylist(name: String, description: String, songs: [Song]) async throws -> Playlist {
        try await requestAuthorization()
        do {
            return try await MusicLibrary.shared.createPlaylist(
                name: name,
                description: description,
                items: songs
            )
        } catch {
            throw MusicKitError.playlistCreationFailed(error.localizedDescription)
        }
    }

    /// Saving to the library needs Sync Library (iCloud Music Library) turned on.
    func libraryAccess() async -> LibraryAccess {
        guard let subscription = try? await MusicSubscription.current else {
            // Can't tell; let the save attempt report any real problem.
            return .available
        }
        if subscription.hasCloudLibraryEnabled { return .available }
        return subscription.canBecomeSubscriber ? .needsSubscription : .needsSyncLibrary
    }

    func fetchUserPlaylists() async throws -> [Playlist] {
        try await requestAuthorization()
        var request = MusicLibraryRequest<Playlist>()
        request.sort(by: \.lastPlayedDate, ascending: false)
        let response = try await request.response()
        return Array(response.items)
    }

    func fetchSongs(from playlist: Playlist) async throws -> [Song] {
        // `genreNames` (used in prompts) comes with library songs, so there's no
        // need for a per-song `.with([.genres])` round trip here.
        let detailed = try await playlist.with([.tracks])
        return detailed.tracks?.compactMap { track in
            if case .song(let song) = track { song } else { nil }
        } ?? []
    }

    func searchLibrarySongs(term: String) async throws -> [Song] {
        try await requestAuthorization()
        var request = MusicLibrarySearchRequest(term: term, types: [Song.self])
        request.limit = 25
        return Array(try await request.response().songs)
    }

    /// Returns a catalog song only when both title and artist match. Earlier versions
    /// fell back to the top search result, which could add a different song by a
    /// different artist; an unmatched song is now reported as "not found" instead.
    @concurrent
    nonisolated static func findCatalogSong(title: String, artist: String) async throws -> Song? {
        let wantedTitle = normalized(title)
        let wantedArtist = normalized(artist)

        let combined = try await searchCatalog(term: "\(title) \(artist)", limit: 5)
        if let match = bestMatch(in: combined, title: wantedTitle, artist: wantedArtist) {
            return match
        }

        // The combined term can miss when the catalog credits the song differently
        // (e.g. "Stan Getz & João Gilberto"). Search the title alone, still requiring the artist.
        let byTitle = try await searchCatalog(term: title, limit: 15)
        return bestMatch(in: byTitle, title: wantedTitle, artist: wantedArtist)
    }

    /// Looks songs up directly by catalog ID (used when reopening History).
    @concurrent
    nonisolated static func fetchCatalogSongs(ids: [String]) async throws -> [String: Song] {
        guard !ids.isEmpty else { return [:] }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids.map { MusicItemID($0) })
        let response = try await request.response()
        return Dictionary(response.items.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private nonisolated static func searchCatalog(term: String, limit: Int) async throws -> MusicItemCollection<Song> {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        return try await request.response().songs
    }

    private nonisolated static func bestMatch(
        in songs: MusicItemCollection<Song>,
        title wantedTitle: String,
        artist wantedArtist: String
    ) -> Song? {
        let artistMatches = songs.filter { song in
            artistsMatch(normalized(song.artistName), wantedArtist)
        }

        if let exact = artistMatches.first(where: { normalized($0.title) == wantedTitle }) {
            return exact
        }

        // Tolerate small title differences such as "Song" vs "Song Part 1".
        return artistMatches.first { song in
            let candidate = normalized(song.title)
            return !candidate.isEmpty && !wantedTitle.isEmpty &&
                (candidate.hasPrefix(wantedTitle) || wantedTitle.hasPrefix(candidate))
        }
    }

    /// Either name containing the other covers "Beyoncé" vs "Beyoncé & JAY-Z".
    nonisolated static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// Lowercases, strips accents, "(feat. X)", "[Remastered]", " - Live" style
    /// suffixes, and punctuation so catalog titles compare fairly with AI output.
    nonisolated static func normalized(_ text: String) -> String {
        var result = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        result = result.replacingOccurrences(
            of: #"\s*[\(\[][^\)\]]*[\)\]]"#,
            with: "",
            options: .regularExpression
        )
        if let dash = result.range(of: " - ") {
            result = String(result[..<dash.lowerBound])
        }
        result = result.replacingOccurrences(
            of: #"\s+(feat\.?|ft\.?|featuring)\s.*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "&", with: " and ")

        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let scalars = result.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
