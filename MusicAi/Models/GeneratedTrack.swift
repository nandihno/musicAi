import Foundation
import MusicKit

/// One row of a generated playlist: the AI suggestion plus its Apple Music match state.
struct GeneratedTrack: Identifiable {
    enum Match {
        case searching
        case found(Song)
        case notFound
        /// The Apple Music search itself failed (network, service), so we don't know yet.
        case searchFailed
        case replacing
    }

    let id = UUID()
    var item: SongItem
    var match: Match = .searching

    var song: Song? {
        if case .found(let song) = match { song } else { nil }
    }

    var isUnmatched: Bool {
        switch match {
        case .notFound, .searchFailed: true
        default: false
        }
    }

    var searchFailed: Bool {
        if case .searchFailed = match { true } else { false }
    }

    var isPending: Bool {
        switch match {
        case .searching, .replacing: true
        case .found, .notFound, .searchFailed: false
        }
    }

    var previewURL: URL? {
        song?.previewAssets?.first?.url
    }
}
