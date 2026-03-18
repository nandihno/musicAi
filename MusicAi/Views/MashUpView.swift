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
                if isLoadingPlaylists {
                    ProgressView("Loading playlists...")
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
            .navigationTitle("Mash Up")
            .task { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
            .overlay {
                if let errorMessage {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                    .padding()
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
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
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
    @State private var selectedSong: Song?

    private let musicKitService = MusicKitService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading songs...")
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
            }
            .tint(.primary)
        }
        .listStyle(.plain)
    }

    private func loadSongs() async {
        isLoading = true
        do {
            songs = try await musicKitService.fetchSongs(from: playlist)
        } catch {
            songs = []
        }
        isLoading = false
    }
}

// MARK: - Song Detail Sheet

struct SongDetailSheet: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let song: Song

    @State private var isGenerating = false
    @State private var generatedSongs: [SongItem] = []
    @State private var artworks: [String: Artwork] = [:]
    @State private var unmatchedSongIDs: Set<String> = []
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var successPlaylistName: String?

    private let claudeService = ClaudeService()
    private let musicKitService = MusicKitService()

    private var metadata: SongMetadata { SongMetadata(from: song) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    songInfoSection
                    generateButton
                    statusSection
                    errorSection
                    successBanner
                    songListSection
                }
                .padding()
            }
            .navigationTitle("Seed Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
    }

    private var metadataBadges: some View {
        let meta = metadata
        let meaningfulGenres = meta.genreNames.filter { $0.lowercased() != "music" }
        let playCountText: String? = meta.playCount.flatMap { $0 > 0 ? "\($0) plays" : nil }
        let yearText: String? = meta.releaseDate.map { "\(Calendar.current.component(.year, from: $0))" }
        let lastPlayedText: String? = meta.lastPlayedDate.map {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last: \(formatter.localizedString(for: $0, relativeTo: Date()))"
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
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task { await generateFromSeed() }
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Generate from this song")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isGenerating)
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
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.subheadline.weight(.semibold))
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Song List

    @ViewBuilder
    private var songListSection: some View {
        if !generatedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                let matched = generatedSongs.count - unmatchedSongIDs.count
                Text("\(matched)/\(generatedSongs.count) matched")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.15))
                    .clipShape(Capsule())

                LazyVStack(spacing: 0) {
                    ForEach(Array(generatedSongs.enumerated()), id: \.element.id) { index, song in
                        SongRowView(
                            index: index,
                            song: song,
                            artwork: artworks[song.id],
                            isUnmatched: unmatchedSongIDs.contains(song.id)
                        )
                        if index < generatedSongs.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Generate

    private func generateFromSeed() async {
        errorMessage = nil
        successPlaylistName = nil
        generatedSongs = []
        artworks = [:]
        unmatchedSongIDs = []
        isGenerating = true

        defer { isGenerating = false }

        do {
            let authStatus = await MusicAuthorization.request()
            guard authStatus == .authorized else {
                errorMessage = "Music access not authorized. Please allow access in Settings."
                return
            }

            statusMessage = "Asking Claude..."
            let context = metadata.claudeContext()
            let songs = try await claudeService.generateFromSeed(
                context: context,
                apiKey: settings.apiKey,
                model: settings.selectedModel
            )
            generatedSongs = songs

            statusMessage = "Searching Apple Music..."
            let seedTitle = song.title
            let playlistName = try await musicKitService.resolveAndCreatePlaylist(
                songs: songs,
                theme: "Inspired by \(seedTitle)",
                onSongResolved: { @MainActor index, found, artwork in
                    let songID = songs[index].id
                    if found {
                        if let artwork {
                            artworks[songID] = artwork
                        }
                    } else {
                        unmatchedSongIDs.insert(songID)
                    }
                    if index == songs.count - 1 {
                        statusMessage = "Creating your playlist..."
                    }
                }
            )

            successPlaylistName = playlistName
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
