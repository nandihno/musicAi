import SwiftUI
import MusicKit

struct SongRowView: View {
    let index: Int
    let song: SongItem
    let artwork: Artwork?
    var isUnmatched: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if isUnmatched {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "xmark")
                            .foregroundStyle(.red)
                    }
            } else if let artwork {
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

            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(isUnmatched ? .red : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(isUnmatched)
                    .foregroundStyle(isUnmatched ? .secondary : .primary)

                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isUnmatched {
                    Text("Not found on Apple Music")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(song.reason)
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(song.genre)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .opacity(isUnmatched ? 0.6 : 1)
    }
}
