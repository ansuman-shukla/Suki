import Foundation

enum MeetingStoreTests {
    static func run() {
        defaultDirectoryLivesUnderAppSupport()
        savesLoadsNewestFirstAndRoundTrips()
        saveOverwritesSameMeeting()
        skipsUnreadableAndForeignFiles()
        deleteRemovesOnlyThatMeeting()
    }

    private static func withTempStore(_ body: (MeetingStore) throws -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        do {
            try body(MeetingStore(directory: directory))
        } catch {
            TestSupport.expect(false, "Unexpected error: \(error)")
        }
    }

    private static func meeting(_ title: String, at seconds: TimeInterval) -> MeetingRecord {
        MeetingRecord(
            title: title,
            date: Date(timeIntervalSince1970: seconds),
            duration: 95,
            segments: [
                MeetingSegment(speaker: .me, start: 0, text: "Synthetic hello."),
                MeetingSegment(speaker: .them, start: 21.5, text: "Synthetic reply.")
            ]
        )
    }

    private static func defaultDirectoryLivesUnderAppSupport() {
        let url = MeetingStore.defaultDirectory
        TestSupport.expectEqual(url.lastPathComponent, "Meetings")
        TestSupport.expectEqual(url.deletingLastPathComponent().lastPathComponent, AppName.displayName)
        TestSupport.expectEqual(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    private static func savesLoadsNewestFirstAndRoundTrips() {
        withTempStore { store in
            TestSupport.expect(store.loadAll().isEmpty, "Missing directory loads as empty")
            let older = meeting("Older", at: 1_000)
            let newer = meeting("Newer", at: 2_000)
            try store.save(older)
            try store.save(newer)
            let loaded = store.loadAll()
            TestSupport.expectEqual(loaded, [newer, older])
            TestSupport.expectEqual(loaded.first?.segments.map(\.text), ["Synthetic hello.", "Synthetic reply."])
            TestSupport.expect(FileManager.default.fileExists(atPath: store.fileURL(for: older.id).path), "One JSON file per meeting")
            TestSupport.expectEqual(store.fileURL(for: older.id).lastPathComponent, "\(older.id.uuidString).json")
        }
    }

    private static func saveOverwritesSameMeeting() {
        withTempStore { store in
            var record = meeting("Before", at: 1_000)
            try store.save(record)
            record.title = "After"
            try store.save(record)
            TestSupport.expectEqual(store.loadAll().map(\.title), ["After"])
        }
    }

    private static func skipsUnreadableAndForeignFiles() {
        withTempStore { store in
            let good = meeting("Good", at: 1_000)
            try store.save(good)
            try Data("{not json".utf8).write(to: store.directory.appendingPathComponent("\(UUID().uuidString).json"))
            try JSONEncoder().encode(meeting("Wrong extension", at: 3_000))
                .write(to: store.directory.appendingPathComponent("chunk.wav"))
            TestSupport.expectEqual(store.loadAll(), [good])
        }
    }

    private static func deleteRemovesOnlyThatMeeting() {
        withTempStore { store in
            let keep = meeting("Keep", at: 1_000)
            let drop = meeting("Drop", at: 2_000)
            try store.save(keep)
            try store.save(drop)
            try store.delete(id: drop.id)
            TestSupport.expectEqual(store.loadAll(), [keep])
            TestSupport.expect(!FileManager.default.fileExists(atPath: store.fileURL(for: drop.id).path), "Deleted file is gone")
            try store.delete(id: drop.id)
            try store.delete(id: UUID())
            TestSupport.expectEqual(store.loadAll(), [keep])
        }
    }
}
