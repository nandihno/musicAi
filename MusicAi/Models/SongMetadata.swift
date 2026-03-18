import Foundation
import MusicKit

struct SongMetadata {
    let title: String
    let artistName: String
    let albumTitle: String?
    let genreNames: [String]
    let duration: TimeInterval?
    let releaseDate: Date?
    let playCount: Int?
    let lastPlayedDate: Date?
    let artwork: Artwork?

    init(from song: Song) {
        self.title = song.title
        self.artistName = song.artistName
        self.albumTitle = song.albumTitle
        self.genreNames = song.genreNames
        self.duration = song.duration
        self.releaseDate = song.releaseDate
        self.playCount = song.playCount
        self.lastPlayedDate = song.lastPlayedDate
        self.artwork = song.artwork
    }

    func claudeContext(songCount: Int = 15) -> String {
        var lines: [String] = []

        lines.append("Seed song: \"\(title)\" by \(artistName)")

        if let album = albumTitle {
            lines.append("Album: \(album)")
        }

        if !genreNames.isEmpty {
            let meaningful = genreNames.filter { $0.lowercased() != "music" }
            if !meaningful.isEmpty {
                lines.append("Genres: \(meaningful.joined(separator: ", "))")
            }
        }

        if let date = releaseDate {
            let year = Calendar.current.component(.year, from: date)
            lines.append("Released: \(year)")
        }

        if let count = playCount, count > 0 {
            lines.append("User play count: \(count) plays — this is clearly a favourite")
        }

        if let last = lastPlayedDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: last, relativeTo: Date())
            lines.append("Last played: \(relative)")
        }

        lines.append("Generate \(songCount) songs with a similar vibe, genre, and energy.")
        lines.append("Do NOT include the seed song itself in the results.")

        return lines.joined(separator: "\n")
    }
}
