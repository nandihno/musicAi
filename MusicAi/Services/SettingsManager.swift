import SwiftUI

@Observable
final class SettingsManager {
    var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "claude_api_key")
        }
    }

    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }
}
