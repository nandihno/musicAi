import AVFoundation
import Observation

/// Plays 30-second Apple Music previews. Works without a subscription.
@Observable
final class PreviewPlayer {
    private(set) var playingID: UUID?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: Task<Void, Never>?

    func toggle(_ track: GeneratedTrack) {
        if playingID == track.id {
            stop()
        } else if let url = track.previewURL {
            play(url, id: track.id)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        endObserver?.cancel()
        endObserver = nil
        playingID = nil
    }

    private func play(_ url: URL, id: UUID) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playingID = id
        player.play()

        endObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                self?.stop()
                break
            }
        }
    }
}
