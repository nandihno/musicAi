import Foundation
import Testing
@testable import MusicAi

struct PromptTests {
    /// SongMetadata normally comes from a MusicKit `Song`; decoding lets tests build one.
    private func seed(title: String = "Corcovado", artist: String = "Stan Getz") throws -> SongMetadata {
        let json = """
        {"title": "\(title)", "artistName": "\(artist)", "genreNames": ["Bossa Nova", "Music"], "playCount": 42}
        """
        return try JSONDecoder().decode(SongMetadata.self, from: Data(json.utf8))
    }

    @Test func themeNameIsCapitalizedAndTruncated() {
        #expect(PlaylistPrompt.theme("rainy  sunday\nbossa").defaultPlaylistName == "\u{1F3B5} Rainy sunday bossa")

        let long = String(repeating: "a", count: 80)
        let name = PlaylistPrompt.theme(long).defaultPlaylistName
        #expect(name.hasSuffix("\u{2026}"))
        #expect(name.count == 2 + 60 + 1)  // emoji + space, 60 chars, ellipsis
    }

    @Test func seedIsRecognisedDespiteFormatting() throws {
        let prompt = PlaylistPrompt.seed(try seed())
        #expect(prompt.isSeed(SongItem(title: "Corcovado (Quiet Nights)", artist: "Stan Getz & João Gilberto", album: "", genre: "", reason: "")))
        #expect(!prompt.isSeed(SongItem(title: "Desafinado", artist: "Stan Getz", album: "", genre: "", reason: "")))
        #expect(!PlaylistPrompt.theme("Corcovado").isSeed(SongItem(title: "Corcovado", artist: "Stan Getz", album: "", genre: "", reason: "")))
    }

    @Test func promptSurvivesCodableRoundTrip() throws {
        let blend = PlaylistPrompt.blend([try seed(), try seed(title: "Teardrop", artist: "Massive Attack")])
        for prompt in [PlaylistPrompt.theme("Afrobeat meets house"), .seed(try seed()), blend] {
            let decoded = try JSONDecoder().decode(PlaylistPrompt.self, from: JSONEncoder().encode(prompt))
            #expect(decoded.summary == prompt.summary)
            #expect(decoded.defaultPlaylistName == prompt.defaultPlaylistName)
        }
    }

    @Test func requestIncludesRefinementsCurrentListAndExclusions() {
        let song = SongItem(title: "Aguas de Marco", artist: "Elis Regina", album: "", genre: "", reason: "")
        let request = PlaylistRequest(
            prompt: .theme("Rainy Sunday bossa nova"),
            count: 12,
            refinements: ["More upbeat", "Only 70s"],
            current: [song],
            excluding: [song]
        )
        let message = request.userMessage

        #expect(message.contains("Musical theme: Rainy Sunday bossa nova"))
        #expect(message.contains("- More upbeat\n- Only 70s"))
        #expect(message.contains("Current playlist:\n- \"Aguas de Marco\" by Elis Regina"))
        #expect(message.contains("exactly 12 songs"))
        #expect(message.contains("Do NOT suggest any of these songs"))
    }

    @Test func plainRequestHasNoRevisionSections() {
        let message = PlaylistRequest(prompt: .theme("Nordic folk"), count: 10).userMessage
        #expect(!message.contains("Current playlist"))
        #expect(!message.contains("refined"))
        #expect(!message.contains("Do NOT suggest"))
    }

    @Test func seedPromptDropsGenericGenre() throws {
        let context = try seed().promptContext()
        #expect(context.contains("Genres: Bossa Nova"))
        #expect(!context.contains("Music,"))
        #expect(context.contains("42 plays"))
    }

    // MARK: - Mash-ups

    private func blend(_ count: Int = 3) throws -> PlaylistPrompt {
        let seeds = [("Corcovado", "Stan Getz"), ("Teardrop", "Massive Attack"), ("Oye Como Va", "Santana")]
        return .blend(try seeds.prefix(count).map { try seed(title: $0.0, artist: $0.1) })
    }

    @Test func blendNameListsTwoSeedsPlusCount() throws {
        #expect(try blend(2).defaultPlaylistName == "\u{1F3B5} Mash-up: Corcovado \u{00D7} Teardrop")
        #expect(try blend(3).defaultPlaylistName == "\u{1F3B5} Mash-up: Corcovado \u{00D7} Teardrop +1")
        #expect(try blend(3).summary == "Mash-up of Corcovado, Teardrop, and Oye Como Va")
    }

    @Test func blendExcludesEverySeed() throws {
        let prompt = try blend()
        #expect(prompt.isSeed(SongItem(title: "Teardrop", artist: "Massive Attack", album: "", genre: "", reason: "")))
        #expect(prompt.isSeed(SongItem(title: "Oye Como Va (Live)", artist: "Santana", album: "", genre: "", reason: "")))
        #expect(!prompt.isSeed(SongItem(title: "Angel", artist: "Massive Attack", album: "", genre: "", reason: "")))
    }

    @Test func blendMessageDescribesEachSeed() throws {
        let message = PlaylistRequest(prompt: try blend(), count: 20).userMessage
        #expect(message.contains("Blend these 3 seed songs"))
        #expect(message.contains("Seed 1:\nSeed song: \"Corcovado\" by Stan Getz"))
        #expect(message.contains("Seed 3:\nSeed song: \"Oye Como Va\" by Santana"))
        #expect(message.contains("exactly 20 songs"))
        #expect(message.contains("Do NOT include any of the seed songs"))
    }
}
