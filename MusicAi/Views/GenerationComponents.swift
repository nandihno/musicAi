import SwiftUI
import MusicKit

// Building blocks shared by the Create Playlist tab and the Mash Up seed sheet.

// MARK: - Generate / Cancel Button

struct GenerateButton: View {
    let title: String
    let systemImage: String
    let isGenerating: Bool
    var isDisabled: Bool = false
    let generate: () -> Void
    let cancel: () -> Void

    var body: some View {
        if isGenerating {
            Button(role: .cancel, action: cancel) {
                Label("Cancel", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        } else {
            Button(action: generate) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.gradientStart)
            .disabled(isDisabled)
        }
    }
}

// MARK: - Status

struct GenerationStatusView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: message)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Error

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - Match Count

struct MatchCountBadge: View {
    let matched: Int
    let total: Int

    var body: some View {
        Text("\(matched)/\(total) matched")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accentGradient)
            .clipShape(Capsule())
            .accessibilityLabel("\(matched) of \(total) songs found on Apple Music")
    }
}

// MARK: - Song Count

struct SongCountPicker: View {
    @Binding var count: Int

    var body: some View {
        Picker("Songs", selection: $count) {
            ForEach(SettingsManager.songCountOptions, id: \.self) { option in
                Text("\(option) songs").tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Theme.gradientStart)
        .accessibilityLabel("Number of songs")
    }
}

// MARK: - List Rows

extension View {
    /// Card-style content placed directly in a plain List, with no row chrome.
    func cardRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    /// Haptics and the Apple Music subscription offer for a generator's lifecycle.
    func generatorFeedback(_ generator: PlaylistGenerator) -> some View {
        @Bindable var generator = generator
        return self
            .sensoryFeedback(.success, trigger: generator.isSaved) { _, saved in saved }
            .sensoryFeedback(.error, trigger: generator.errorMessage) { _, new in new != nil }
            .musicSubscriptionOffer(isPresented: $generator.showSubscriptionOffer)
    }
}

// MARK: - Error Helpers

extension Error {
    /// Whether retrying the same request could succeed. Configuration problems
    /// (missing key, Apple Intelligence off, no Music access) need the user to act first.
    var isRetryable: Bool {
        switch self {
        case let error as ClaudeService.ClaudeError:
            error.isRetryable
        case let error as FoundationModelsService.FMError:
            if case .unavailable = error { false } else { true }
        case let error as MusicKitService.MusicKitError:
            error.isRetryable
        default:
            true
        }
    }

    /// True for errors raised because the user (or the view disappearing) cancelled the task.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
