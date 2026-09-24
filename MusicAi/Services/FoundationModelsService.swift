import Foundation
import FoundationModels

@Generable
nonisolated struct GeneratedPlaylist {
    // The exact count is requested in the prompt; the guide caps runaway output.
    @Guide(description: "Real songs that authentically exist on Apple Music", .maximumCount(40))
    var songs: [GeneratedSong]
}

@Generable
nonisolated struct GeneratedSong {
    @Guide(description: "Song title")
    var title: String
    @Guide(description: "Artist name")
    var artist: String
    @Guide(description: "Album name")
    var album: String
    @Guide(description: "Primary genre")
    var genre: String
    @Guide(description: "One sentence, max 15 words, explaining why this song fits")
    var reason: String
}

nonisolated struct FoundationModelsService: PlaylistProvider {
    enum FMError: LocalizedError {
        case unavailable(String)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .generationFailed(let detail): "Apple Intelligence couldn't generate a playlist: \(detail)"
            }
        }
    }

    var displayName: String { "Apple Intelligence" }

    /// Returns a human-readable reason if unavailable, or nil if ready to use.
    static func unavailabilityReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        default:
            return "Apple Intelligence isn't available right now."
        }
    }

    func streamSongs(
        for prompt: PlaylistPrompt,
        count: Int,
        excluding: [SongItem]
    ) -> AsyncThrowingStream<SongItem, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(prompt: prompt, count: count, excluding: excluding) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch let error as FMError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: FMError.generationFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        prompt: PlaylistPrompt,
        count: Int,
        excluding: [SongItem],
        onSong: (SongItem) -> Void
    ) async throws {
        if let reason = Self.unavailabilityReason() {
            throw FMError.unavailable(reason)
        }

        let session = LanguageModelSession(instructions: instructions(for: prompt))
        let responseStream = session.streamResponse(
            to: prompt.userMessage(count: count, excluding: excluding),
            generating: GeneratedPlaylist.self
        )

        // Each snapshot holds the whole playlist so far. A song is complete once
        // the model has moved on to the next one; the last is flushed at the end.
        var emitted = 0
        var latest: [GeneratedSong.PartiallyGenerated] = []

        for try await snapshot in responseStream {
            latest = snapshot.content.songs ?? []
            while emitted < latest.count - 1 {
                if let song = SongItem(latest[emitted]) { onSong(song) }
                emitted += 1
            }
        }

        while emitted < latest.count {
            if let song = SongItem(latest[emitted]) { onSong(song) }
            emitted += 1
        }
    }

    private func instructions(for prompt: PlaylistPrompt) -> String {
        switch prompt {
        case .theme:
            """
            You are a world-class music curator with deep knowledge of global \
            music genres, cross-cultural fusions, and music history. Given a \
            musical theme or fusion concept, generate a playlist of real songs \
            that authentically represent that theme. Every song must genuinely \
            exist on Apple Music. DO NOT invent songs. Never repeat the same \
            artist more than twice. Vary the era, mixing classic and contemporary picks.
            """
        case .seed:
            """
            You are a world-class music curator. The user will describe a seed \
            song from their library. Generate a playlist of songs that share a \
            similar genre, mood, or musical energy, would feel natural alongside \
            the seed song, and genuinely exist on Apple Music. DO NOT include the \
            seed song itself. Never repeat the same artist more than twice.
            """
        }
    }
}

extension SongItem {
    /// Nil until the model has produced at least a title and artist.
    nonisolated init?(_ partial: GeneratedSong.PartiallyGenerated) {
        guard let title = partial.title, !title.isEmpty,
              let artist = partial.artist, !artist.isEmpty else {
            return nil
        }
        self.init(
            title: title,
            artist: artist,
            album: partial.album ?? "",
            genre: partial.genre ?? "",
            reason: partial.reason ?? ""
        )
    }
}
