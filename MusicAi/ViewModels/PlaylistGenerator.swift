import Foundation
import MusicKit
import Observation
import SwiftUI  // Array.move(fromOffsets:toOffset:) / remove(atOffsets:)

/// Drives one generate → review → save session. Songs stream in from the AI
/// and are matched against Apple Music as they arrive; nothing is written to
/// the user's library until they tap Save.
@Observable
final class PlaylistGenerator {
    enum Activity: Equatable {
        case generating
        case replacing
        case rechecking
        case saving
    }

    private(set) var tracks: [GeneratedTrack] = []
    private(set) var activity: Activity?
    private(set) var savedPlaylist: Playlist?
    private(set) var errorMessage: String?
    private(set) var providerName = ""
    private(set) var requestedCount = 0

    /// Editable before saving.
    var playlistName = ""
    /// Bound to `.musicSubscriptionOffer` when saving needs an Apple Music subscription.
    var showSubscriptionOffer = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var retryAction: (() -> Void)?
    @ObservationIgnored private var prompt: PlaylistPrompt?
    @ObservationIgnored private var provider: (any PlaylistProvider)?
    @ObservationIgnored private var lastSearchError: Error?

    private let musicKitService = MusicKitService()

    // MARK: - Derived State

    var isBusy: Bool { activity != nil }
    var hasResults: Bool { !tracks.isEmpty }
    var isSaved: Bool { savedPlaylist != nil }
    var canEdit: Bool { hasResults && !isBusy && !isSaved }
    var matchedCount: Int { tracks.filter { $0.song != nil }.count }
    /// Songs Apple Music definitely doesn't have (not ones whose search failed).
    var unmatchedCount: Int { tracks.filter { if case .notFound = $0.match { true } else { false } }.count }
    var failedSearchCount: Int { tracks.filter(\.searchFailed).count }
    var pendingCount: Int { tracks.filter(\.isPending).count }
    var canRetry: Bool { retryAction != nil && !isBusy }

    var statusMessage: String {
        switch activity {
        case .generating:
            if tracks.isEmpty {
                "Asking \(providerName)\u{2026}"
            } else if tracks.count < requestedCount {
                "Asking \(providerName)\u{2026} \(tracks.count)/\(requestedCount)"
            } else if pendingCount > 0 {
                "Matching on Apple Music\u{2026} \(tracks.count - pendingCount)/\(tracks.count)"
            } else {
                "Finishing up\u{2026}"
            }
        case .replacing:
            "Finding replacements\u{2026}"
        case .rechecking:
            "Checking Apple Music\u{2026}"
        case .saving:
            "Saving to Apple Music\u{2026}"
        case nil:
            ""
        }
    }

    // MARK: - Generate

    func generate(_ prompt: PlaylistPrompt, provider: any PlaylistProvider, count: Int) {
        guard !isBusy else { return }
        self.prompt = prompt
        self.provider = provider
        activity = .generating  // set synchronously so a double tap can't start two runs
        task = Task { await runGeneration(prompt, provider: provider, count: count) }
    }

    func cancel() {
        task?.cancel()
    }

    func retry() {
        let action = retryAction
        retryAction = nil
        action?()
    }

    /// Clears results so the user can start a new playlist.
    func reset() {
        guard !isBusy else { return }
        tracks = []
        savedPlaylist = nil
        errorMessage = nil
        retryAction = nil
        playlistName = ""
    }

    private func runGeneration(_ prompt: PlaylistPrompt, provider: any PlaylistProvider, count: Int) async {
        tracks = []
        savedPlaylist = nil
        clearError()
        providerName = provider.displayName
        requestedCount = count
        playlistName = prompt.defaultPlaylistName

        defer {
            activity = nil
            task = nil
        }

        do {
            try await musicKitService.requestAuthorization()

            try await streamAndMatch(
                provider.streamSongs(for: prompt, count: count, excluding: []),
                prompt: prompt,
                limit: count
            ) { track in
                self.tracks.append(track)
                return track.id
            }
            try Task.checkCancellation()

            if tracks.isEmpty {
                throw GeneratorError.noSongs
            }
            reportSearchFailures()
        } catch let error where error.isCancellation || Task.isCancelled {
            tracks = []
        } catch {
            fail(with: error) { [weak self] in
                self?.generate(prompt, provider: provider, count: count)
            }
        }
    }

    // MARK: - Edit

    func remove(atOffsets offsets: IndexSet) {
        guard canEdit else { return }
        tracks.remove(atOffsets: offsets)
    }

    func remove(_ track: GeneratedTrack) {
        guard canEdit else { return }
        tracks.removeAll { $0.id == track.id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard canEdit else { return }
        tracks.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Replace

    func replaceUnmatched() {
        replace(ids: tracks.filter { if case .notFound = $0.match { true } else { false } }.map(\.id))
    }

    func replace(_ track: GeneratedTrack) {
        replace(ids: [track.id])
    }

    private func replace(ids: [UUID]) {
        guard canEdit, !ids.isEmpty, let prompt, let provider else { return }
        activity = .replacing
        task = Task { await runReplacement(ids: ids, prompt: prompt, provider: provider) }
    }

    /// Asks for new songs and swaps them into the given rows in place,
    /// keeping the user's ordering. Rows the model couldn't fill stay as they were.
    private func runReplacement(ids: [UUID], prompt: PlaylistPrompt, provider: any PlaylistProvider) async {
        clearError()
        var slots = ids
        var originals: [UUID: GeneratedTrack.Match] = [:]
        for id in ids {
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { continue }
            originals[id] = tracks[index].match
            tracks[index].match = .replacing
        }

        defer {
            // Anything not replaced goes back to how it was.
            for (id, match) in originals {
                if let index = tracks.firstIndex(where: { $0.id == id }) {
                    tracks[index].match = match
                }
            }
            activity = nil
            task = nil
        }

        do {
            try await streamAndMatch(
                provider.streamSongs(for: prompt, count: ids.count, excluding: tracks.map(\.item)),
                prompt: prompt,
                limit: ids.count
            ) { newTrack in
                let slot = slots.removeFirst()
                guard let index = self.tracks.firstIndex(where: { $0.id == slot }) else { return nil }
                originals[slot] = nil
                self.tracks[index] = newTrack
                return newTrack.id
            }
            reportSearchFailures()
        } catch let error where error.isCancellation || Task.isCancelled {
            // Leave the playlist as it was.
        } catch {
            fail(with: error) { [weak self] in
                self?.replace(ids: ids)
            }
        }
    }

    // MARK: - Recheck

    /// Re-runs Apple Music searches that failed (e.g. after the network comes back).
    func recheckFailedSearches() {
        let ids = tracks.filter(\.searchFailed).map(\.id)
        guard canEdit, !ids.isEmpty else { return }
        activity = .rechecking
        task = Task { await runRecheck(ids: ids) }
    }

    private func runRecheck(ids: [UUID]) async {
        clearError()
        defer {
            activity = nil
            task = nil
        }

        let items: [(UUID, SongItem)] = ids.compactMap { id in
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
            tracks[index].match = .searching
            return (id, tracks[index].item)
        }

        await withTaskGroup(of: Void.self) { group in
            for (id, item) in items {
                group.addTask { await self.search(item, for: id) }
            }
        }

        if Task.isCancelled {
            // Put anything still searching back to failed so it can be retried.
            for id in ids {
                if let index = tracks.firstIndex(where: { $0.id == id }), tracks[index].isPending {
                    tracks[index].match = .searchFailed
                }
            }
            return
        }
        reportSearchFailures()
    }

    // MARK: - Save

    func save() {
        guard canEdit, matchedCount > 0 else { return }
        activity = .saving
        task = Task { await runSave() }
    }

    private func runSave() async {
        clearError()
        defer {
            activity = nil
            task = nil
        }

        switch await musicKitService.libraryAccess() {
        case .available:
            break
        case .needsSubscription:
            showSubscriptionOffer = true
            return
        case .needsSyncLibrary:
            fail(with: MusicKitService.MusicKitError.syncLibraryOff, retry: nil)
            return
        }

        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = prompt?.defaultPlaylistName ?? "MusicAI Playlist"

        do {
            savedPlaylist = try await musicKitService.createPlaylist(
                name: name.isEmpty ? fallbackName : name,
                description: prompt?.playlistDescription ?? "Generated by MusicAI",
                songs: tracks.compactMap(\.song)
            )
        } catch {
            fail(with: error) { [weak self] in self?.save() }
        }
    }

    // MARK: - Streaming & Matching

    /// Consumes the AI stream, dropping duplicates and the seed song, and starts
    /// an Apple Music search for each new song immediately. `insert` places the
    /// track and returns its id (or nil if there's nowhere to put it).
    private func streamAndMatch(
        _ stream: AsyncThrowingStream<SongItem, Error>,
        prompt: PlaylistPrompt,
        limit: Int,
        insert: (GeneratedTrack) -> UUID?
    ) async throws {
        var seen = Set(tracks.map(\.item.dedupeKey))
        var accepted = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            for try await item in stream {
                guard accepted < limit,
                      !prompt.isSeed(item),
                      seen.insert(item.dedupeKey).inserted,
                      let id = insert(GeneratedTrack(item: item)) else {
                    continue
                }
                accepted += 1

                group.addTask { await self.search(item, for: id) }
            }
            try await group.waitForAll()
        }
    }

    /// Runs off the main actor; only the result is applied back on it.
    private nonisolated func search(_ item: SongItem, for id: UUID) async {
        let match: GeneratedTrack.Match
        do {
            let song = try await MusicKitService.findCatalogSong(title: item.title, artist: item.artist)
            match = song.map { .found($0) } ?? .notFound
        } catch {
            match = .searchFailed
            await recordSearchError(error)
        }
        guard !Task.isCancelled else { return }
        await applyMatch(match, to: id)
    }

    private func applyMatch(_ match: GeneratedTrack.Match, to id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].match = match
    }

    private func recordSearchError(_ error: Error) {
        lastSearchError = error
    }

    /// A failed search isn't the same as "Apple Music doesn't have it", so say so
    /// and offer to retry just those searches.
    private func reportSearchFailures() {
        let failed = failedSearchCount
        guard failed > 0 else { return }
        let detail = lastSearchError?.localizedDescription ?? "Unknown error"
        errorMessage = "Couldn't check \(failed) \(failed == 1 ? "song" : "songs") on Apple Music (\(detail))."
        retryAction = { [weak self] in self?.recheckFailedSearches() }
    }

    // MARK: - Errors

    private enum GeneratorError: LocalizedError {
        case noSongs

        var errorDescription: String? {
            "No songs came back. Try rephrasing your prompt."
        }
    }

    private func clearError() {
        errorMessage = nil
        retryAction = nil
        lastSearchError = nil
    }

    private func fail(with error: Error, retry: (() -> Void)?) {
        errorMessage = error.localizedDescription
        retryAction = error.isRetryable ? retry : nil
    }
}
