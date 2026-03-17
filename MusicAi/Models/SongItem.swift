import Foundation

struct SongItem: Codable, Identifiable, Sendable {
    var id: String { "\(artist) - \(title)" }
    let title: String
    let artist: String
    let album: String
    let genre: String
    let reason: String
}
