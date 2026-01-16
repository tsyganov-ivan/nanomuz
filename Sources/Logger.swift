import Foundation

class Logger {
    static let shared = Logger()
    var enabled = false

    private var lastMessages: [String: Date] = [:]
    private let dedupeInterval: TimeInterval = 5.0
    private let maxEntries = 100
    private var fileHandle: FileHandle?

    static var logFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Nanomuz")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nanomuz.log")
    }

    private init() {}

    func log(_ message: String, key: String? = nil) {
        guard enabled else { return }

        let dedupeKey = key ?? message
        let now = Date()

        if let lastTime = lastMessages[dedupeKey],
           now.timeIntervalSince(lastTime) < dedupeInterval {
            return
        }

        lastMessages[dedupeKey] = now
        cleanupIfNeeded()

        write(message)
    }

    func logAlways(_ message: String) {
        guard enabled else { return }
        write(message)
    }

    private func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        if fileHandle == nil {
            FileManager.default.createFile(atPath: Self.logFileURL.path, contents: nil)
            fileHandle = try? FileHandle(forWritingTo: Self.logFileURL)
            fileHandle?.seekToEndOfFile()
        }

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private func cleanupIfNeeded() {
        guard lastMessages.count > maxEntries else { return }
        let cutoff = Date().addingTimeInterval(-dedupeInterval * 2)
        lastMessages = lastMessages.filter { $0.value > cutoff }
    }

    func deleteLogFile() {
        fileHandle?.closeFile()
        fileHandle = nil
        try? FileManager.default.removeItem(at: Self.logFileURL)
    }
}
