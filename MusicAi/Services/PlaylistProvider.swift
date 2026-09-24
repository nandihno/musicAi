import Foundation

/// An AI backend that suggests songs. Songs are streamed so the UI can show
/// each one (and start matching it on Apple Music) as soon as it's generated.
nonisolated protocol PlaylistProvider: Sendable {
    /// Shown in status messages, e.g. "Asking Claude…".
    var displayName: String { get }

    func streamSongs(
        for prompt: PlaylistPrompt,
        count: Int,
        excluding: [SongItem]
    ) -> AsyncThrowingStream<SongItem, Error>
}

/// Pulls complete top-level JSON objects out of a JSON array that arrives in
/// arbitrary chunks, e.g. `[{"a":1},{"a` then `":2}]` yields `{"a":1}` then `{"a":2}`.
nonisolated struct JSONObjectStreamScanner {
    private var depth = 0
    private var inString = false
    private var escaping = false
    private var current = ""

    mutating func feed(_ chunk: String) -> [String] {
        var completed: [String] = []

        for character in chunk {
            if depth > 0 {
                current.append(character)
            }

            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"" where depth > 0:
                inString = true
            case "{":
                depth += 1
                if depth == 1 { current = "{" }
            case "}" where depth > 0:
                depth -= 1
                if depth == 0 {
                    completed.append(current)
                    current = ""
                }
            default:
                break
            }
        }

        return completed
    }
}
