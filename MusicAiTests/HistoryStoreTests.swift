import Foundation
import SwiftData
import Testing
@testable import MusicAi

struct HistoryStoreTests {
    private let container: ModelContainer
    private let store: HistoryStore

    init() throws {
        container = try ModelContainer(
            for: Schema(versionedSchema: HistorySchemaV1.self),
            migrationPlan: HistoryMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = HistoryStore(context: container.mainContext)
    }

    private func track(_ title: String, _ match: GeneratedTrack.Match = .notFound) -> GeneratedTrack {
        GeneratedTrack(item: SongItem(title: title, artist: "Artist", album: "", genre: "", reason: ""), match: match)
    }

    private func snapshot(_ titles: [String], refinements: [String] = [], savedAt: Date? = nil) -> HistorySnapshot {
        HistorySnapshot(
            name: "My Mix",
            prompt: .theme("Late night jazz"),
            refinements: refinements,
            providerName: "Claude",
            tracks: titles.map { track($0) },
            savedAt: savedAt
        )
    }

    private func allEntries() throws -> [PlaylistHistoryEntry] {
        try container.mainContext.fetch(FetchDescriptor<PlaylistHistoryEntry>())
    }

    @Test func createsEntryWithOrderedTracks() throws {
        let id = try #require(store.upsert(id: nil, snapshot: snapshot(["C", "A", "B"])))
        let entry = try #require(store.entry(for: id))

        #expect(entry.name == "My Mix")
        #expect(entry.promptSummary == "Late night jazz")
        #expect(entry.orderedTracks.map(\.title) == ["C", "A", "B"])
        #expect(entry.trackCount == 3)
        #expect(entry.orderedTracks.allSatisfy { $0.status == .notFound })
        #expect(entry.prompt?.summary == "Late night jazz")
    }

    @Test func updatingReusesEntryAndReplacesTracks() throws {
        let id = store.upsert(id: nil, snapshot: snapshot(["A", "B", "C"]))
        let sameID = store.upsert(id: id, snapshot: snapshot(["B", "D"], refinements: ["More upbeat"]))

        #expect(sameID == id)
        let entries = try allEntries()
        #expect(entries.count == 1)
        #expect(entries[0].orderedTracks.map(\.title) == ["B", "D"])
        #expect(entries[0].refinements == ["More upbeat"])
        // Old tracks are deleted, not orphaned.
        #expect(try container.mainContext.fetchCount(FetchDescriptor<HistoryTrack>()) == 2)
    }

    @Test func savedDateIsKeptOnLaterUpdates() throws {
        let savedAt = Date(timeIntervalSince1970: 1_000_000)
        let id = store.upsert(id: nil, snapshot: snapshot(["A"], savedAt: savedAt))
        store.upsert(id: id, snapshot: snapshot(["A", "B"]))

        #expect(try allEntries().first?.savedAt == savedAt)
    }

    @Test func unconfirmedMatchesAreStoredAsUnchecked() throws {
        var snap = snapshot([])
        snap.tracks = [track("A", .searching), track("B", .searchFailed), track("C", .notFound)]
        let id = try #require(store.upsert(id: nil, snapshot: snap))

        let statuses = try #require(store.entry(for: id)).orderedTracks.map(\.status)
        #expect(statuses == [.unchecked, .unchecked, .notFound])
    }

    @Test func deletingEntryCascadesToTracks() throws {
        let id = try #require(store.upsert(id: nil, snapshot: snapshot(["A", "B"])))
        container.mainContext.delete(try #require(store.entry(for: id)))
        try container.mainContext.save()

        #expect(try container.mainContext.fetchCount(FetchDescriptor<HistoryTrack>()) == 0)
        // An update after deletion creates a fresh entry rather than failing.
        #expect(store.upsert(id: id, snapshot: snapshot(["A"])) != nil)
        #expect(try allEntries().count == 1)
    }
}
