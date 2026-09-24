import Foundation

nonisolated struct ClaudeService: PlaylistProvider {
    enum ClaudeError: LocalizedError {
        case missingAPIKey
        case invalidAPIKey
        case rateLimited
        case overloaded
        case offline
        case timedOut
        case httpError(statusCode: Int, message: String)
        case invalidResponse
        case jsonParseError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Claude API key is missing. Add it in Settings (gear icon)."
            case .invalidAPIKey:
                "Your Claude API key was rejected. Check it in Settings."
            case .rateLimited:
                "Claude is rate limiting requests. Wait a moment and try again."
            case .overloaded:
                "Claude is busy right now. Try again shortly."
            case .offline:
                "You're offline. Reconnect, or switch to Apple Intelligence in Settings."
            case .timedOut:
                "Claude took too long to respond. Try again."
            case .httpError(let code, let message):
                "Claude returned an error (\(code)): \(message)"
            case .invalidResponse:
                "Claude sent an unexpected response. Try again."
            case .jsonParseError:
                "Couldn't read the playlist Claude returned. Try again."
            }
        }

        var isRetryable: Bool {
            switch self {
            case .missingAPIKey, .invalidAPIKey: false
            default: true
            }
        }
    }

    let apiKey: String
    let model: ClaudeModel

    var displayName: String { "Claude" }

    func streamSongs(
        for prompt: PlaylistPrompt,
        count: Int,
        excluding: [SongItem]
    ) -> AsyncThrowingStream<SongItem, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(
                        system: systemPrompt(for: prompt),
                        user: prompt.userMessage(count: count, excluding: excluding),
                        maxTokens: max(1024, count * 120 + 512)
                    ) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Prompts

    private static let outputFormat = """
    Output format (a JSON array and nothing else):
    [
      {
        "title": "song title",
        "artist": "artist name",
        "album": "album name",
        "genre": "primary genre",
        "reason": "one sentence why this fits"
      }
    ]
    """

    private func systemPrompt(for prompt: PlaylistPrompt) -> String {
        switch prompt {
        case .theme:
            """
            You are a world-class music curator with deep knowledge of global \
            music genres, cross-cultural fusions, and music history.
            Given a musical theme or fusion concept, you return a playlist \
            of real songs that authentically represent that theme.
            Rules you must always follow:
            - Return ONLY a valid JSON array, no markdown, no explanation.
            - Each object must have exactly these keys: \
              "title", "artist", "album", "genre", "reason"
            - "reason" must be one sentence max 15 words explaining the musical \
              connection to the theme
            - Every song must genuinely exist on Apple Music — no invented songs
            - For fusion themes (e.g. "latin with indian"), alternate between \
              both musical worlds and include songs that truly blend them
            - Prioritise songs that are authentic to the genre, not just popular
            - Vary the era — mix classic and contemporary
            - Never repeat the same artist more than twice
            - For niche or fusion genres, be creative and accurate — \
              don't default to obvious mainstream choices
            \(Self.outputFormat)
            """
        case .seed:
            """
            You are a world-class music curator with deep knowledge of global \
            music genres, cross-cultural fusions, and music history.
            The user will give you details about a specific seed song from their \
            library. Your job is to generate a playlist of songs that:
            - Share a similar genre, mood, or musical energy to the seed song
            - Would feel natural to listen to alongside the seed song
            - Come from the same era OR are modern songs with the same vibe
            - Are authentic to the genre — not just popular mainstream picks
            - Actually exist on Apple Music
            Rules:
            - Return ONLY a valid JSON array, no markdown, no explanation
            - Each object must have exactly: "title", "artist", "album", "genre", "reason"
            - "reason" is one sentence (max 15 words) explaining the sonic connection
            - Never include the seed song itself in the results
            - Vary the era intelligently — don't return every song from the same year
            - Never repeat the same artist more than twice
            - If the seed has multiple genres (e.g. Latin + Jazz), honour that fusion
            - If the user has high play count, they know this genre deeply — \
              go deeper and more authentic, not mainstream
            \(Self.outputFormat)
            """
        }
    }

    // MARK: - Request

    /// Sends a streaming Messages request and calls `onSong` for each complete
    /// song object as soon as its closing brace arrives.
    private func stream(
        system: String,
        user: String,
        maxTokens: Int,
        onSong: (SongItem) -> Void
    ) async throws {
        guard !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                var body = Data()
                for try await byte in bytes { body.append(byte) }
                throw mapHTTPError(statusCode: httpResponse.statusCode, data: body)
            }

            var scanner = JSONObjectStreamScanner()
            var songCount = 0
            let decoder = JSONDecoder()

            // Server-sent events: we only need the `data:` lines.
            for try await line in bytes.lines {
                guard line.hasPrefix("data:"),
                      let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                switch event["type"] as? String {
                case "content_block_delta":
                    guard let delta = event["delta"] as? [String: Any],
                          let text = delta["text"] as? String else { continue }
                    for object in scanner.feed(text) {
                        // Skip a malformed object rather than failing the whole playlist.
                        if let song = try? decoder.decode(SongItem.self, from: Data(object.utf8)) {
                            songCount += 1
                            onSong(song)
                        }
                    }
                case "error":
                    throw mapStreamError(event["error"] as? [String: Any])
                default:
                    break
                }
            }

            if songCount == 0 {
                throw ClaudeError.jsonParseError("No songs found in the response")
            }
        } catch let error as URLError {
            throw mapURLError(error)
        }
    }

    // MARK: - Errors

    private func mapURLError(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled:
            CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
            ClaudeError.offline
        case .timedOut:
            ClaudeError.timedOut
        default:
            error
        }
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> ClaudeError {
        switch statusCode {
        case 401, 403:
            return .invalidAPIKey
        case 429:
            return .rateLimited
        case 500..<600:
            return .overloaded
        default:
            // Anthropic errors look like {"type":"error","error":{"type":"...","message":"..."}}
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            return .httpError(statusCode: statusCode, message: message ?? "Unknown error")
        }
    }

    /// Errors can also arrive mid-stream as an `error` event.
    private func mapStreamError(_ error: [String: Any]?) -> ClaudeError {
        switch error?["type"] as? String {
        case "overloaded_error", "api_error": .overloaded
        case "rate_limit_error": .rateLimited
        case "authentication_error", "permission_error": .invalidAPIKey
        default: .httpError(statusCode: 200, message: error?["message"] as? String ?? "Unknown error")
        }
    }
}
