import SwiftUI
import MusicKit

struct MashUpView: View {
    @Environment(SettingsManager.self) private var settings

    @State private var playlists: [Playlist] = []
    @State private var isLoadingPlaylists = true
    @State private var errorMessage: String?

    private let musicKitService = MusicKitService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingPlaylists && playlists.isEmpty {
                    ProgressView("Loading playlists...")
                } else if let errorMessage, playlists.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load Playlists", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadPlaylists() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.gradientStart)
                    }
                } else if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("Add playlists to your Apple Music library to get started.")
                    )
                } else {
                    playlistList
                }
            }
            .appBackground()
            .navigationTitle("Mash Up")
            .settingsToolbar()
            .task { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
            .safeAreaInset(edge: .top) {
                // A refresh failure while playlists are already showing.
                if let errorMessage, !playlists.isEmpty {
                    ErrorBanner(message: errorMessage) {
                        Task { await loadPlaylists() }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var playlistList: some View {
        List(playlists) { playlist in
            NavigationLink(value: playlist) {
                HStack(spacing: 12) {
                    if let artwork = playlist.artwork {
                        ArtworkImage(artwork, width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 50, height: 50)
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                    }
                    Text(playlist.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(playlist.name)
            }
            .listRowBackground(Theme.gradientStart.opacity(0.06))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistSongsView(playlist: playlist)
        }
    }

    private func loadPlaylists() async {
        isLoadingPlaylists = true
        errorMessage = nil
        do {
            playlists = try await musicKitService.fetchUserPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPlaylists = false
    }
}

// MARK: - Song List for a Playlist

struct PlaylistSongsView: View {
    let playlist: Playlist

    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSong: Song?

    private let musicKitService = MusicKitService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading songs...")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Songs", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        Task { await loadSongs() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gradientStart)
                }
            } else if songs.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("This playlist has no songs.")
                )
            } else {
                songList
            }
        }
        .appBackground()
        .navigationTitle(playlist.name)
        .task { await loadSongs() }
        .sheet(item: $selectedSong) { song in
            SongDetailSheet(song: song)
        }
    }

    private var songList: some View {
        List(songs) { song in
            Button {
                selectedSong = song
            } label: {
                HStack(spacing: 12) {
                    if let artwork = song.artwork {
                        ArtworkImage(artwork, width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(song.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(song.title) by \(song.artistName)")
            }
            .accessibilityHint("Opens options to generate a playlist from this song")
            .tint(.primary)
            .listRowBackground(Theme.gradientStart.opacity(0.06))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadSongs() async {
        isLoading = true
        errorMessage = nil
        do {
            songs = try await musicKitService.fetchSongs(from: playlist)
        } catch {
            songs = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Song Detail Sheet

struct SongDetailSheet: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let song: Song

    @State private var generator = PlaylistGenerator()
    @State private var previewPlayer = PreviewPlayer()
    @State private var metadata: SongMetadata

    init(song: Song) {
        self.song = song
        _metadata = State(initialValue: SongMetadata(from: song))
    }

    var body: some View {
        NavigationStack {
            List {
                songInfoSection
                    .cardRow()
                generateSection
                    .cardRow()
                GenerationFeedbackRows(generator: generator)
                GeneratedPlaylistSection(generator: generator, previewPlayer: previewPlayer)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("Seed Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if generator.canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .generatorFeedback(generator)
            // Closing the sheet mid-run shouldn't leave work running in the background.
            .onDisappear {
                generator.cancel()
                previewPlayer.stop()
            }
        }
    }

    // MARK: - Song Info

    private var songInfoSection: some View {
        VStack(spacing: 16) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8, y: 4)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 4) {
                Text(song.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(song.artistName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if let album = song.albumTitle {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            metadataBadges
        }
        .frame(maxWidth: .infinity)
    }

    private var metadataBadges: some View {
        let meta = metadata
        let meaningfulGenres = meta.genreNames.filter { $0.lowercased() != "music" }
        let playCountText: String? = meta.playCount.flatMap { $0 > 0 ? "\($0) plays" : nil }
        let yearText: String? = meta.releaseDate.map { "\(Calendar.current.component(.year, from: $0))" }
        let lastPlayedText: String? = meta.lastPlayedDate.map {
            "Last: \($0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        }

        return FlowLayout(spacing: 8) {
            ForEach(meaningfulGenres, id: \.self) { genre in
                badge(genre, icon: "guitars")
            }
            if let text = playCountText {
                badge(text, icon: "play.fill")
            }
            if let text = yearText {
                badge(text, icon: "calendar")
            }
            if let text = lastPlayedText {
                badge(text, icon: "clock")
            }
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.accentGradient)
        .clipShape(Capsule())
    }

    // MARK: - Generate

    private var generateSection: some View {
        @Bindable var settings = settings

        return VStack(spacing: 8) {
            HStack {
                Text("Playlist length")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                SongCountPicker(count: $settings.songCount)
                    .disabled(generator.isBusy)
            }

            GenerateButton(
                title: generator.hasResults ? "Generate Again" : "Generate from this song",
                systemImage: "wand.and.stars",
                isGenerating: generator.activity == .generating,
                isDisabled: generator.isBusy,
                generate: startGeneration,
                cancel: generator.cancel
            )
        }
    }

    private func startGeneration() {
        previewPlayer.stop()
        generator.generate(.seed(metadata), provider: settings.provider, count: settings.songCount)
    }
}
