import SwiftUI
import MusicKit

struct TrackRowView: View {
    let index: Int
    let track: GeneratedTrack
    var isPlaying: Bool = false

    private var song: SongItem { track.item }

    var body: some View {
        HStack(spacing: 12) {
            leadingArtwork

            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(track.isUnmatched ? .red : .secondary)
                .monospacedDigit()
                .frame(minWidth: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(track.isUnmatched)
                    .foregroundStyle(track.isUnmatched ? .secondary : .primary)

                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                detailLine
            }

            Spacer()

            if !song.genre.isEmpty {
                Text(song.genre)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentGradient)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.gradientStart.opacity(track.isUnmatched ? 0.04 : 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(track.isUnmatched ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isPlaying ? .startsMediaSession : [])
    }

    @ViewBuilder
    private var leadingArtwork: some View {
        ZStack {
            switch track.match {
            case .searching, .replacing:
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            case .notFound:
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red.opacity(0.1))
                    .overlay {
                        Image(systemName: "xmark")
                            .foregroundStyle(.red)
                    }
            case .searchFailed:
                RoundedRectangle(cornerRadius: 8)
                    .fill(.orange.opacity(0.12))
                    .overlay {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    }
            case .found(let match):
                if let artwork = match.artwork {
                    ArtworkImage(artwork, width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                }
            }

            if isPlaying {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.45))
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var detailLine: some View {
        switch track.match {
        case .notFound:
            Text("Not found on Apple Music")
                .font(.caption2)
                .foregroundStyle(.red)
        case .searchFailed:
            Text("Couldn't check Apple Music")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .replacing:
            Text("Finding a replacement\u{2026}")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .searching, .found:
            if !song.reason.isEmpty {
                Text(song.reason)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }

    private var accessibilityDescription: String {
        let status = switch track.match {
        case .notFound: "Not found on Apple Music."
        case .searchFailed: "Couldn't check Apple Music."
        case .searching: "Searching Apple Music."
        case .replacing: "Finding a replacement."
        case .found: song.reason
        }
        let playing = isPlaying ? " Playing preview." : ""
        return "\(index + 1). \(song.title) by \(song.artist). \(song.genre). \(status)\(playing)"
    }
}
