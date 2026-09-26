import Foundation
import Testing
@testable import MusicAi

struct JSONObjectStreamScannerTests {
    private static let response = """
    ```json
    [
      {"title": "Mas Que Nada", "artist": "Jorge Ben", "album": "A", "genre": "MPB", "reason": "Has {braces} and \\"quotes\\""},
      {"title": "Chove Chuva", "artist": "Jorge Ben", "album": "B", "genre": "Samba", "reason": "nested {\\"a\\": [1, 2]}"},
      {"title": "Last", "artist": "C", "album": "D", "genre": "E", "reason": "ends with }"}
    ]
    ```
    """

    @Test("Yields the same objects however the text is chunked", arguments: 1...40)
    func chunking(size: Int) throws {
        var scanner = JSONObjectStreamScanner()
        var objects: [String] = []
        var index = Self.response.startIndex
        while index < Self.response.endIndex {
            let end = Self.response.index(index, offsetBy: size, limitedBy: Self.response.endIndex) ?? Self.response.endIndex
            objects += scanner.feed(String(Self.response[index..<end]))
            index = end
        }

        let songs = try objects.map { try JSONDecoder().decode(SongItem.self, from: Data($0.utf8)) }
        #expect(songs.map(\.title) == ["Mas Que Nada", "Chove Chuva", "Last"])
        #expect(songs[0].reason == "Has {braces} and \"quotes\"")
    }

    @Test func ignoresTextOutsideTheArray() {
        var scanner = JSONObjectStreamScanner()
        #expect(scanner.feed("Here you go: \"not an object\" ").isEmpty)
        #expect(scanner.feed("[{\"a\": 1}]").count == 1)
    }
}

struct NormalizationTests {
    @Test(arguments: [
        ("Mas Que Nada (feat. The Black Eyed Peas)", "Mas Que Nada"),
        ("Here Comes the Sun - Remastered 2009", "here comes the sun"),
        ("Águas de Março", "Aguas de Marco"),
        ("Crazy in Love [feat. JAY-Z]", "Crazy In Love"),
        ("Tokyo Drift ft. Someone", "Tokyo Drift")
    ])
    func equivalentTitles(catalog: String, suggested: String) {
        #expect(MusicKitService.normalized(catalog) == MusicKitService.normalized(suggested))
    }

    @Test func artistMatchingAllowsCollaborations() {
        let getzGilberto = MusicKitService.normalized("Stan Getz & João Gilberto")
        #expect(MusicKitService.artistsMatch(getzGilberto, MusicKitService.normalized("Joao Gilberto")))
        #expect(!MusicKitService.artistsMatch(getzGilberto, MusicKitService.normalized("Caetano Veloso")))
        #expect(!MusicKitService.artistsMatch("", "anyone"))
    }

    @Test func dedupeKeyIgnoresFeaturingAndCase() {
        let a = SongItem(title: "Song (feat. X)", artist: "Band", album: "", genre: "", reason: "")
        let b = SongItem(title: "song", artist: "BAND", album: "", genre: "", reason: "")
        #expect(a.dedupeKey == b.dedupeKey)
    }
}
