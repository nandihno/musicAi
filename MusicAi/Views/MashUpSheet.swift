import SwiftUI
import MusicKit
import SwiftData

/// Generates a playlist from one seed song, or blends up to five into a mash-up.
struct MashUpSheet: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let seeds: [Song]

    @State private var generator = PlaylistGenerator()
    @State private var previewPlayer = PreviewPlayer()
    @State private var metadata: [SongMetadata]

    init(seeds: [Song]) {
        self.seeds = seeds
        _metadata = State(initialValue: seeds.map(SongMetadata.init(from:)))
    }

    private var isBlend: Bool { seeds.count > 1 }

    private var prompt: PlaylistPrompt? {
        switch metadata.count {
        case 0: nil
        case 1: .seed(metadata[0])
        default: .blend(metadata)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                seedsSection
                    .cardRow()
                generateSection
                    .cardRow()
                GenerationFeedbackRows(generator: generator)
                GeneratedPlaylistSection(generator: generator, previewPlayer: previewPlayer)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle(isBlend ? "Mash-up" : "Seed Song")
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
            .onAppear { generator.attachHistory(modelContext) }
            // Closing the sheet mid-run shouldn't leave work running in the background.
            .onDisappear {
                generator.cancel()
                previewPlayer.stop()
            }
        }
    }

    // MARK: - Seeds

    @ViewBuilder
    private var seedsSection: some View {
        if let seed = seeds.first, let meta = metadata.first, !isBlend {
            singleSeed(seed, meta)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mashing up \(seeds.count) songs")
                    .font(.headline)
                ForEach(Array(zip(seeds, metadata)), id: \.0.id) { seed, meta in
                    HStack(spacing: 12) {
                        ArtworkThumbnail(artwork: seed.artwork, size: 52, placeholder: "music.note")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(seed.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(seed.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            badges(for: meta, compact: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
    }

    private func singleSeed(_ song: Song, _ meta: SongMetadata) -> some View {
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

            badges(for: meta, compact: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func badges(for meta: SongMetadata, compact: Bool) -> some View {
        let genres = meta.genreNames.filter { $0.lowercased() != "music" }
        let playCount = meta.playCount.flatMap { $0 > 0 ? "\($0) plays" : nil }
        let year = meta.releaseDate.map { "\(Calendar.current.component(.year, from: $0))" }
        let lastPlayed = compact ? nil : meta.lastPlayedDate.map {
            "Last: \($0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        }

        return FlowLayout(spacing: compact ? 4 : 8) {
            ForEach(compact ? Array(genres.prefix(2)) : genres, id: \.self) { genre in
                badge(genre, icon: "guitars", compact: compact)
            }
            if let year {
                badge(year, icon: "calendar", compact: compact)
            }
            if let playCount {
                badge(playCount, icon: "play.fill", compact: compact)
            }
            if let lastPlayed {
                badge(lastPlayed, icon: "clock", compact: compact)
            }
        }
    }

    private func badge(_ text: String, icon: String, compact: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(compact ? .caption2.weight(.bold) : .caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 3 : 6)
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
                title: generator.hasResults ? "Generate Again"
                    : isBlend ? "Mash up these \(seeds.count) songs" : "Generate from this song",
                systemImage: "wand.and.stars",
                isGenerating: generator.activity == .generating,
                isDisabled: generator.isBusy || prompt == nil,
                generate: startGeneration,
                cancel: generator.cancel
            )
        }
    }

    private func startGeneration() {
        guard let prompt else { return }
        previewPlayer.stop()
        generator.generate(prompt, provider: settings.provider, count: settings.songCount)
    }
}
