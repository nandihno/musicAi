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

                RefineCard(generator: generator)
                    .cardRow()
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
                    .onSubmit { generator.commitName() }
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

            if let savedAt = generator.previouslySavedAt {
                Label(
                    "Saved to Apple Music \(savedAt.formatted(.relative(presentation: .named))). Saving again creates a new copy.",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

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
            if generator.canRefine {
                Button {
                    generator.refine(moreLike: track)
                } label: {
                    Label("More Like This", systemImage: "plus.square.on.square")
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

// MARK: - Refine Card

/// Follow-up instructions ("more upbeat", "only 70s") that revise the whole playlist.
struct RefineCard: View {
    let generator: PlaylistGenerator

    @State private var instruction = ""
    @FocusState private var isFocused: Bool

    private static let quickRefinements = [
        "More upbeat",
        "More chill",
        "Less mainstream",
        "More variety",
        "Older songs",
        "Newer songs"
    ]

    private var isRefining: Bool { generator.activity == .refining }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Refine", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))

            FlowLayout(spacing: 8) {
                ForEach(Self.quickRefinements, id: \.self) { suggestion in
                    Button {
                        submit(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.gradientStart.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.gradientStart)
                    .disabled(!generator.canRefine)
                    .accessibilityHint("Revises the playlist")
                }
            }

            HStack {
                TextField("Or describe a change\u{2026}", text: $instruction)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { submit(instruction) }
                    .disabled(!generator.canRefine && !isRefining)

                if isRefining {
                    Button("Cancel", action: generator.cancel)
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        submit(instruction)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .tint(Theme.gradientStart)
                    .disabled(!generator.canRefine || instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Refine playlist")
                }
            }

            if !generator.refinements.isEmpty {
                Text("Refined: \(generator.refinements.joined(separator: " \u{00B7} "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .labelStyle(.titleAndIcon)
        .padding()
        .background(Theme.gradientStart.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func submit(_ text: String) {
        guard generator.canRefine, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isFocused = false
        generator.refine(text)
        instruction = ""
    }
}
