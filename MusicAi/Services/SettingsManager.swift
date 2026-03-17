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
    var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "claude_api_key")
        }
    }

    var selectedModel: ClaudeModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "claude_model")
        }
    }

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        let savedModel = UserDefaults.standard.string(forKey: "claude_model") ?? ""
        self.selectedModel = ClaudeModel(rawValue: savedModel) ?? .sonnet
    }
}
