import SwiftUI
import MusicKit

struct CreatePlaylistView: View {
    @Environment(SettingsManager.self) private var settings

    @State private var theme = ""
    @State private var generator = PlaylistGenerator()
    @State private var previewPlayer = PreviewPlayer()
    @FocusState private var isPromptFocused: Bool

    private static let promptIdeas = [
        "Rainy Sunday bossa nova",
        "Afrobeat meets deep house",
        "Night drive through Tokyo",
        "90s Brazilian funk",
        "Latin jazz with Indian classical",
        "Sunny 70s soul road trip",
        "Nordic folk for focus",
        "Desert blues and psych rock"
    ]

    private var trimmedTheme: String {
        theme.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedTheme.isEmpty && !generator.isBusy
    }

    var body: some View {
        NavigationStack {
            List {
                promptSection
                    .cardRow()
                suggestionsSection
                GenerationFeedbackRows(generator: generator)
                GeneratedPlaylistSection(generator: generator, previewPlayer: previewPlayer)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle("Create Playlist")
            .toolbar {
                if generator.canEdit {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .settingsToolbar()
            .generatorFeedback(generator)
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        @Bindable var settings = settings

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What kind of music?")
                    .font(.title3.weight(.bold))
                Spacer()
                SongCountPicker(count: $settings.songCount)
                    .disabled(generator.isBusy)
            }

            TextField(
                "e.g. tropical cumbia jazz",
                text: $theme,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .focused($isPromptFocused)
            .submitLabel(.go)
            .onChange(of: theme) { _, newValue in
                // A vertical TextField inserts a newline on Return instead of
                // calling onSubmit, so treat that newline as "Go".
                guard newValue.contains("\n") else { return }
                theme = newValue.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                if canGenerate { startGeneration() }
            }

            GenerateButton(
                title: generator.hasResults ? "Generate Again" : "Generate Playlist",
                systemImage: "sparkles",
                isGenerating: generator.activity == .generating,
                isDisabled: !canGenerate,
                generate: startGeneration,
                cancel: generator.cancel
            )
        }
        .cardBackground()
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if !generator.hasResults && !generator.isBusy && generator.errorMessage == nil {
            VStack(alignment: .leading, spacing: 12) {
                Label("Need inspiration?", systemImage: "lightbulb")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(Self.promptIdeas, id: \.self) { idea in
                        Button {
                            theme = idea
                            isPromptFocused = false
                        } label: {
                            Text(idea)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.gradientStart.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.gradientStart)
                        .accessibilityHint("Fills in the prompt")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardRow()
        }
    }

    // MARK: - Generate

    private func startGeneration() {
        guard canGenerate else { return }
        isPromptFocused = false
        previewPlayer.stop()
        generator.generate(.theme(trimmedTheme), provider: settings.provider, count: settings.songCount)
    }
}
