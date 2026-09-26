import Foundation

/// Everything a provider needs for one call: the original prompt plus the
/// session's refinements, and optionally the current list to revise or songs to avoid.
nonisolated struct PlaylistRequest: Sendable {
    var prompt: PlaylistPrompt
    var count: Int
    /// Follow-up instructions such as "more upbeat", oldest first.
    var refinements: [String] = []
    /// When non-empty, the model revises this list instead of starting fresh.
    var current: [SongItem] = []
    /// Songs the model must not suggest (already in the playlist or unavailable).
    var excluding: [SongItem] = []

    /// The user message sent to the model.
    var userMessage: String {
        var lines = prompt.baseLines(count: count)

        if !refinements.isEmpty {
            lines.append("")
            lines.append("The listener has refined the playlist with these requests (oldest first). Follow all of them, giving the latest the most weight:")
            lines.append(contentsOf: refinements.map { "- \($0)" })
        }

        if !current.isEmpty {
            lines.append("")
            lines.append("Current playlist:")
            lines.append(contentsOf: current.map { "- \"\($0.title)\" by \($0.artist)" })
            lines.append("")
            lines.append("Return a revised playlist of exactly \(count) songs. Keep songs from the current playlist that still fit the requests, and replace the ones that don't.")
        }

        if !excluding.isEmpty {
            lines.append("")
            lines.append("Do NOT suggest any of these songs (already in the playlist or unavailable on Apple Music):")
            lines.append(contentsOf: excluding.map { "- \"\($0.title)\" by \($0.artist)" })
        }

        return lines.joined(separator: "\n")
    }
}
