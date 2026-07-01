import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("Use Apple Intelligence", isOn: $settings.useAppleIntelligence)
                } header: {
                    Text("On-Device AI")
                } footer: {
                    if settings.useAppleIntelligence, let reason = FoundationModelsService.unavailabilityReason() {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Generates playlists entirely on your device with Apple Intelligence — no API key or network needed, but with less music knowledge than Claude.")
                    }
                }

                Section {
                    SecureField("sk-ant-...", text: $settings.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Your key is stored locally on this device.")
                }
                .disabled(settings.useAppleIntelligence)
                .opacity(settings.useAppleIntelligence ? 0.4 : 1)

                Section {
                    Picker("Model", selection: $settings.selectedModel) {
                        ForEach(ClaudeModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Claude Model")
                } footer: {
                    Text("Sonnet is more creative. Haiku is faster and cheaper.")
                }
                .disabled(settings.useAppleIntelligence)
                .opacity(settings.useAppleIntelligence ? 0.4 : 1)
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
