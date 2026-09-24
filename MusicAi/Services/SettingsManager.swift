import SwiftUI

enum ClaudeModel: String, CaseIterable, Sendable {
    case sonnet = "claude-sonnet-4-6"
    case haiku = "claude-haiku-4-5-20251001"

    var displayName: String {
        switch self {
        case .sonnet: "Sonnet 4.6"
        case .haiku: "Haiku 4.5"
        }
    }
}

@Observable
final class SettingsManager {
    private static let apiKeyKey = "claude_api_key"

    var apiKey: String {
        didSet {
            KeychainStore.set(apiKey, for: Self.apiKeyKey)
        }
    }

    var selectedModel: ClaudeModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "claude_model")
        }
    }

    var useAppleIntelligence: Bool {
        didSet {
            UserDefaults.standard.set(useAppleIntelligence, forKey: "use_apple_intelligence")
        }
    }

    static let songCountOptions = [10, 15, 20, 30]

    var songCount: Int {
        didSet {
            UserDefaults.standard.set(songCount, forKey: "song_count")
        }
    }

    /// The AI backend the user picked, configured with their current settings.
    var provider: any PlaylistProvider {
        if useAppleIntelligence {
            FoundationModelsService()
        } else {
            ClaudeService(apiKey: apiKey, model: selectedModel)
        }
    }

    init() {
        self.apiKey = Self.loadAPIKey()
        let savedModel = UserDefaults.standard.string(forKey: "claude_model") ?? ""
        self.selectedModel = ClaudeModel(rawValue: savedModel) ?? .sonnet
        self.useAppleIntelligence = UserDefaults.standard.bool(forKey: "use_apple_intelligence")
        let savedCount = UserDefaults.standard.integer(forKey: "song_count")
        self.songCount = Self.songCountOptions.contains(savedCount) ? savedCount : 15
    }

    /// Reads the key from the Keychain, migrating it out of UserDefaults
    /// (where earlier versions stored it in plaintext) on first launch.
    private static func loadAPIKey() -> String {
        if let stored = KeychainStore.string(for: apiKeyKey) {
            return stored
        }

        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: apiKeyKey) else { return "" }
        KeychainStore.set(legacy, for: apiKeyKey)
        defaults.removeObject(forKey: apiKeyKey)
        return legacy
    }
}
