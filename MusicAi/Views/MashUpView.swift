import SwiftUI
import MusicKit

/// Pick up to five seed songs (from playlists, a library search, or whatever's
/// playing) and blend them into one playlist.
struct MashUpView: View {
    @State private var selection = SeedSelection()
    @State private var searchText = ""
    @State private var showMashUp = false

    var body: some View {
        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    PlaylistBrowser()
                } else {
                    LibrarySearchResults(term: searchText)
                }
            }
            .appBackground()
            .navigationTitle("Mash Up")
            .searchable(text: $searchText, prompt: "Search songs in your library")
            .settingsToolbar()
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistSongsView(playlist: playlist)
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty {
                    SeedTray { showMashUp = true }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection.songs.count)
            .sheet(isPresented: $showMashUp) {
                MashUpSheet(seeds: selection.songs)
            }
        }
        .environment(selection)
    }
}

// MARK: - Playlists + Now Playing

private struct PlaylistBrowser: View {
    @Environment(SeedSelection.self) private var selection

    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var nowPlayingMessage: String?
    @State private var isAddingNowPlaying = false

    private let musicKitService = MusicKitService()

    var body: some View {
        List {
            Section {
                nowPlayingRow
            } footer: {
                Text("Pick up to \(SeedSelection.maxSeeds) songs from your playlists or search, then mash them up.")
            }

            Section("Your Playlists") {
                playlistRows
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .task { await loadPlaylists() }
        .refreshable { await loadPlaylists() }
    }

    private var nowPlayingRow: some View {
        Button {
            Task { await addNowPlaying() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add what's playing now")
                        .font(.body.weight(.semibold))
                    if let nowPlayingMessage {
                        Text(nowPlayingMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAddingNowPlaying {
                    ProgressView()
                }
            }
        }
        .tint(.primary)
        .disabled(isAddingNowPlaying)
    }

    @ViewBuilder
    private var playlistRows: some View {
        if isLoading && playlists.isEmpty {
            HStack {
                ProgressView()
                Text("Loading playlists\u{2026}")
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage, playlists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't load playlists", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await loadPlaylists() }
                }
                .buttonStyle(.bordered)
            }
        } else if playlists.isEmpty {
            Text("Add playlists to your Apple Music library, or search for songs above.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(playlists) { playlist in
                NavigationLink(value: playlist) {
                    HStack(spacing: 12) {
                        ArtworkThumbnail(artwork: playlist.artwork, size: 50, placeholder: "music.note.list")
                        Text(playlist.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(playlist.name)
                }
            }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        errorMessage = nil
        do {
            playlists = try await musicKitService.fetchUserPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addNowPlaying() async {
        isAddingNowPlaying = true
        defer { isAddingNowPlaying = false }
        do {
            let (song, result) = try await selection.addNowPlaying()
            nowPlayingMessage = switch result {
            case .added: "Added \u{201C}\(song.title)\u{201D}"
            case .alreadyAdded: "\u{201C}\(song.title)\u{201D} is already in your mash-up"
            case .full: "You can mash up to \(SeedSelection.maxSeeds) songs"
            }
        } catch {
            nowPlayingMessage = error.localizedDescription
        }
    }
}

// MARK: - Playlist Songs

struct PlaylistSongsView: View {
    let playlist: Playlist

    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                List(songs) { song in
                    SelectableSongRow(song: song)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .appBackground()
        .navigationTitle(playlist.name)
        .task { await loadSongs() }
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

// MARK: - Library Search

private struct LibrarySearchResults: View {
    let term: String

    @State private var songs: [Song] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let musicKitService = MusicKitService()

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if songs.isEmpty && !isSearching {
                ContentUnavailableView.search(text: term)
            } else {
                List(songs) { song in
                    SelectableSongRow(song: song)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .top) {
                    if isSearching && songs.isEmpty {
                        ProgressView().padding()
                    }
                }
            }
        }
        // Restarts (and cancels the previous search) whenever the term changes.
        .task(id: term) {
            do {
                try await Task.sleep(for: .milliseconds(300))  // debounce typing
            } catch {
                return
            }
            await search()
        }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let results = try await musicKitService.searchLibrarySongs(term: term)
            guard !Task.isCancelled else { return }
            songs = results
        } catch where !Task.isCancelled {
            errorMessage = error.localizedDescription
        } catch {}
    }
}

// MARK: - Selectable Row

/// A library song that can be added to (or removed from) the mash-up.
struct SelectableSongRow: View {
    @Environment(SeedSelection.self) private var selection
    let song: Song

    private var isSelected: Bool { selection.contains(song) }
    private var canAdd: Bool { isSelected || !selection.isFull }

    var body: some View {
        Button {
            selection.toggle(song)
        } label: {
            HStack(spacing: 12) {
                ArtworkThumbnail(artwork: song.artwork, size: 44, placeholder: "music.note")
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.gradientStart) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .opacity(canAdd ? 1 : 0.5)
        .listRowBackground(Theme.gradientStart.opacity(isSelected ? 0.14 : 0.06))
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(song.title) by \(song.artistName)")
        .accessibilityValue(isSelected ? "In mash-up" : "")
        .accessibilityHint(
            isSelected ? "Removes it from the mash-up"
                : canAdd ? "Adds it to the mash-up"
                : "The mash-up already has \(SeedSelection.maxSeeds) songs"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Seed Tray

/// Floating tray showing the picked songs and the button to mash them up.
private struct SeedTray: View {
    @Environment(SeedSelection.self) private var selection
    let mashUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selection.songs) { song in
                        seedChip(song)
                    }
                }
            }

            HStack {
                Text("\(selection.songs.count)/\(SeedSelection.maxSeeds) songs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Clear", role: .destructive) {
                    selection.clear()
                }
                .font(.caption.weight(.semibold))
                Spacer()
                Button(action: mashUp) {
                    Label(
                        selection.songs.count == 1 ? "Generate from 1 song" : "Mash Up \(selection.songs.count) songs",
                        systemImage: "wand.and.stars"
                    )
                    .labelStyle(.titleAndIcon)
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gradientStart)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.gradientStart.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func seedChip(_ song: Song) -> some View {
        HStack(spacing: 6) {
            ArtworkThumbnail(artwork: song.artwork, size: 28, placeholder: "music.note")
            Text(song.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
            Button {
                selection.remove(song)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(song.title)")
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Theme.gradientStart.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Artwork

struct ArtworkThumbnail: View {
    let artwork: Artwork?
    let size: CGFloat
    let placeholder: String

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: placeholder)
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .accessibilityHidden(true)
    }
}
