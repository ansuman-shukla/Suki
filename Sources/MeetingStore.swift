import Foundation

/// Saves each meeting transcript as `<id>.json`. Text only; chunk audio never lands here.
final class MeetingStore {
    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = MeetingStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent(AppName.displayName, isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    }

    /// Newest first. Unreadable files are skipped rather than failing the whole list.
    func loadAll() -> [MeetingRecord] {
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(MeetingRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func save(_ meeting: MeetingRecord) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(meeting).write(to: fileURL(for: meeting.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
