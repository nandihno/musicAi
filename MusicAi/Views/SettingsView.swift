import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
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
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
