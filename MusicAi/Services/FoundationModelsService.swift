import Foundation
import FoundationModels

@Generable
struct GeneratedPlaylist {
    @Guide(description: "Exactly 15 real songs that authentically exist on Apple Music", .count(15))
    var songs: [GeneratedSong]
}

@Generable
struct GeneratedSong {
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

extension SongItem {
    init(_ generated: GeneratedSong) {
        self.init(
            title: generated.title,
            artist: generated.artist,
            album: generated.album,
            genre: generated.genre,
            reason: generated.reason
        )
    }
}

actor FoundationModelsService {
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

    func generatePlaylist(theme: String) async throws -> [SongItem] {
        if let reason = Self.unavailabilityReason() {
            throw FMError.unavailable(reason)
        }

        let session = LanguageModelSession {
            """
            You are a world-class music curator with deep knowledge of global \
            music genres, cross-cultural fusions, and music history. Given a \
            musical theme or fusion concept, generate a playlist of exactly \
            15 real songs that authentically represent that theme. Every song \
            must genuinely exist on Apple Music. DO NOT invent songs. \
            Never repeat the same artist more than twice. Vary the era, mixing \
            classic and contemporary picks.
            """
        }

        do {
            let response = try await session.respond(
                to: "Musical theme: \(theme)",
                generating: GeneratedPlaylist.self
            )
            return response.content.songs.map(SongItem.init)
        } catch let error as FMError {
            throw error
        } catch {
            throw FMError.generationFailed(error.localizedDescription)
        }
    }

    func generateFromSeed(context: String) async throws -> [SongItem] {
        if let reason = Self.unavailabilityReason() {
            throw FMError.unavailable(reason)
        }

        let session = LanguageModelSession {
            """
            You are a world-class music curator. The user will describe a seed \
            song from their library. Generate a playlist of 15 songs that \
            share a similar genre, mood, or musical energy, would feel natural \
            alongside the seed song, and genuinely exist on Apple Music. \
            DO NOT include the seed song itself. Never repeat the same artist \
            more than twice.
            """
        }

        do {
            let response = try await session.respond(
                to: context,
                generating: GeneratedPlaylist.self
            )
            return response.content.songs.map(SongItem.init)
        } catch let error as FMError {
            throw error
        } catch {
            throw FMError.generationFailed(error.localizedDescription)
        }
    }
}
