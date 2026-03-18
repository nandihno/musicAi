import Foundation

actor ClaudeService {
    enum ClaudeError: LocalizedError {
        case missingAPIKey
        case httpError(statusCode: Int, body: String)
        case invalidResponse
        case jsonParseError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Claude API key is missing. Please set it in Settings."
            case .httpError(let code, let body):
                "HTTP \(code): \(body)"
            case .invalidResponse:
                "Invalid response from Claude API."
            case .jsonParseError(let detail):
                "Failed to parse playlist JSON: \(detail)"
            }
        }
    }

    func generatePlaylist(theme: String, apiKey: String, model: ClaudeModel) async throws -> [SongItem] {
        guard !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
        You are a world-class music curator with deep knowledge of global \
        music genres, cross-cultural fusions, and music history.
        Given a musical theme or fusion concept, you return a playlist \
        of exactly 15 real songs that authentically represent that theme.
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
        """

        let userMessage = """
        Musical theme: \(theme)

        Output format (no other text):
        [
          {
            "title": "song title",
            "artist": "artist name",
            "album": "album name",
            "genre": "primary genre",
            "reason": "one sentence why this fits the theme"
          }
        ]
        """

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        return try parseSongs(from: text)
    }

    func generateFromSeed(context: String, apiKey: String, model: ClaudeModel) async throws -> [SongItem] {
        guard !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let systemPrompt = """
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
        - Vary the era intelligently — don't return 15 songs from the same year
        - Never repeat the same artist more than twice
        - If the seed has multiple genres (e.g. Latin + Jazz), honour that fusion
        - If the user has high play count, they know this genre deeply — \
          go deeper and more authentic, not mainstream
        Output format (no other text):
        [
          {
            "title": "song title",
            "artist": "artist name",
            "album": "album name",
            "genre": "primary genre",
            "reason": "one sentence sonic connection to the seed"
          }
        ]
        """

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": context]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeError.invalidResponse
        }

        return try parseSongs(from: text)
    }

    private func parseSongs(from text: String) throws -> [SongItem] {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fences if present
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            let stripped = lines.drop { $0.hasPrefix("```") }
                .reversed().drop { $0.hasPrefix("```") }.reversed()
            cleaned = stripped.joined(separator: "\n")
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ClaudeError.jsonParseError("Could not encode text as UTF-8")
        }

        do {
            let songs = try JSONDecoder().decode([SongItem].self, from: jsonData)
            return songs
        } catch {
            throw ClaudeError.jsonParseError(error.localizedDescription)
        }
    }
}
