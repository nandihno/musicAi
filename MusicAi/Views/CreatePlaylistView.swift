import SwiftUI
import MusicKit

struct CreatePlaylistView: View {
    @Environment(SettingsManager.self) private var settings

    @State private var showSettings = false
    @State private var theme = ""
    @State private var songs: [SongItem] = []
    @State private var artworks: [String: Artwork] = [:]
    @State private var isGenerating = false
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var successPlaylistName: String?
    @State private var unmatchedSongIDs: Set<String> = []

    private let claudeService = ClaudeService()
    private let foundationModelsService = FoundationModelsService()
    private let musicKitService = MusicKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    promptSection
                    statusSection
                    errorSection
                    successBanner
                    songListSection
                }
                .padding()
            }
            .appBackground()
            .navigationTitle("Create Playlist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What kind of music?")
                .font(.title3.weight(.bold))

            TextField(
                "e.g. tropical cumbia jazz",
                text: $theme,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Generate Playlist")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gradientStart)
                .disabled(theme.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)

                if !songs.isEmpty {
                    let matched = songs.count - unmatchedSongIDs.count
                    Text("\(matched)/\(songs.count) matched")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accentGradient)
                        .clipShape(Capsule())
                }
            }
        }
        .cardBackground()
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        if isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: statusMessage)
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Success Banner

    @ViewBuilder
    private var successBanner: some View {
        if let name = successPlaylistName {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Added to Apple Music")
                    .font(.subheadline.weight(.bold))
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Song List

    @ViewBuilder
    private var songListSection: some View {
        if !songs.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(
                        index: index,
                        song: song,
                        artwork: artworks[song.id],
                        isUnmatched: unmatchedSongIDs.contains(song.id)
                    )
                    if index < songs.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Generate

    private func generate() async {
        errorMessage = nil
        successPlaylistName = nil
        songs = []
        artworks = [:]
        unmatchedSongIDs = []
        isGenerating = true

        defer { isGenerating = false }

        do {
            // Step 0: Ensure MusicKit authorization
            let authStatus = await MusicAuthorization.request()
            guard authStatus == .authorized else {
                errorMessage = "Music access not authorized. Please allow access in Settings."
                return
            }

            // Step 1: Ask Claude or Apple Intelligence
            let generatedSongs: [SongItem]
            if settings.useAppleIntelligence {
                statusMessage = "\u{1F34E} Asking Apple Intelligence\u{2026}"
                generatedSongs = try await foundationModelsService.generatePlaylist(theme: theme)
            } else {
                statusMessage = "\u{1F916} Asking Claude\u{2026}"
                generatedSongs = try await claudeService.generatePlaylist(
                    theme: theme,
                    apiKey: settings.apiKey,
                    model: settings.selectedModel
                )
            }
            songs = generatedSongs

            // Step 2: Search Apple Music & create playlist
            statusMessage = "\u{1F50D} Searching Apple Music\u{2026}"
            let capturedSongs = generatedSongs
            let playlistName = try await musicKitService.resolveAndCreatePlaylist(
                songs: capturedSongs,
                theme: theme,
                onSongResolved: { @MainActor index, found, artwork in
                    let songID = capturedSongs[index].id
                    if found {
                        if let artwork {
                            artworks[songID] = artwork
                        }
                    } else {
                        unmatchedSongIDs.insert(songID)
                    }
                    if index == capturedSongs.count - 1 {
                        statusMessage = "\u{1F3B5} Creating your playlist\u{2026}"
                    }
                }
            )

            successPlaylistName = playlistName
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
