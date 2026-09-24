import SwiftUI
import MusicKit

/// Status/error rows for a generator, placed inside a List.
struct GenerationFeedbackRows: View {
    let generator: PlaylistGenerator

    var body: some View {
        if generator.isBusy {
            GenerationStatusView(message: generator.statusMessage)
                .cardRow()
        }
        if let errorMessage = generator.errorMessage {
            ErrorBanner(message: errorMessage, retry: retryAction)
                .cardRow()
        }
    }

    private var retryAction: (() -> Void)? {
        guard generator.canRetry else { return nil }
        return { generator.retry() }
    }
}

/// The review-before-save UI: playlist name, save / replace actions, and the
/// editable song list. Place inside a List (it contributes two Sections).
struct GeneratedPlaylistSection: View {
    @Bindable var generator: PlaylistGenerator
    let previewPlayer: PreviewPlayer

    var body: some View {
        if generator.hasResults {
            Section {
                if let playlist = generator.savedPlaylist {
                    SavedPlaylistCard(playlist: playlist) {
                        previewPlayer.stop()
                        generator.reset()
                    }
                    .cardRow()
                } else {
                    reviewCard
                        .cardRow()
                }
            }

            Section {
                ForEach(Array(generator.tracks.enumerated()), id: \.element.id) { index, track in
                    row(for: track, at: index)
                }
                .onMove(perform: moveAction)
                .onDelete(perform: deleteAction)
            }
        }
    }

    // Nil disables reordering / edit-mode delete while busy or after saving.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard generator.canEdit else { return nil }
        return { generator.move(fromOffsets: $0, toOffset: $1) }
    }

    private var deleteAction: ((IndexSet) -> Void)? {
        guard generator.canEdit else { return nil }
        return { generator.remove(atOffsets: $0) }
    }

    // MARK: - Review Card

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Playlist name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Playlist name", text: $generator.playlistName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .disabled(!generator.canEdit)
            }

            HStack {
                MatchCountBadge(matched: generator.matchedCount, total: generator.tracks.count)
                Spacer()
                if generator.unmatchedCount > 0 {
                    Button {
                        generator.replaceUnmatched()
                    } label: {
                        Label("Replace \(generator.unmatchedCount) missing", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(!generator.canEdit)
                }
            }

            Button {
                previewPlayer.stop()
                generator.save()
            } label: {
                Label("Save \(generator.matchedCount) songs to Apple Music", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.gradientStart)
            .disabled(!generator.canEdit || generator.matchedCount == 0)

            Text("Tap a song to preview it. Swipe to remove or replace, or tap Edit to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)  // List rows otherwise drop button icons
        .cardBackground()
    }

    // MARK: - Rows

    private func row(for track: GeneratedTrack, at index: Int) -> some View {
        Button {
            previewPlayer.toggle(track)
        } label: {
            TrackRowView(index: index, track: track, isPlaying: previewPlayer.playingID == track.id)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(track.previewURL == nil ? "" : "Plays a preview")
        .swipeActions(edge: .trailing) {
            if generator.canEdit {
                Button(role: .destructive) {
                    stopIfPlaying(track)
                    generator.remove(track)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                Button {
                    stopIfPlaying(track)
                    generator.replace(track)
                } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if track.previewURL != nil {
                Button {
                    previewPlayer.toggle(track)
                } label: {
                    previewPlayer.playingID == track.id
                        ? Label("Stop Preview", systemImage: "stop.fill")
                        : Label("Play Preview", systemImage: "play.fill")
                }
            }
            if generator.canEdit {
                Button {
                    stopIfPlaying(track)
                    generator.replace(track)
                } label: {
                    Label("Replace Song", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    stopIfPlaying(track)
                    generator.remove(track)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }

    private func stopIfPlaying(_ track: GeneratedTrack) {
        if previewPlayer.playingID == track.id {
            previewPlayer.stop()
        }
    }
}

// MARK: - Saved Card

struct SavedPlaylistCard: View {
    let playlist: Playlist
    let startOver: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var playbackFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved to Apple Music")
                        .font(.subheadline.weight(.bold))
                    Text(playlist.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            HStack {
                Button {
                    Task { await play() }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.gradientStart)

                Button {
                    openInMusic()
                } label: {
                    Label("Open Music", systemImage: "arrow.up.forward.app")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.gradientStart)
            }

            if playbackFailed {
                Text("Couldn't start playback here. Open the playlist in Music instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Start a new playlist", action: startOver)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .labelStyle(.titleAndIcon)
        .padding()
        .background(.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Plays through the Music app so playback continues after leaving MusicAI.
    private func play() async {
        let player = SystemMusicPlayer.shared
        player.queue = [playlist]
        do {
            try await player.play()
            playbackFailed = false
        } catch {
            playbackFailed = true
        }
    }

    private func openInMusic() {
        if let url = playlist.url ?? URL(string: "music://") {
            openURL(url)
        }
    }
}
