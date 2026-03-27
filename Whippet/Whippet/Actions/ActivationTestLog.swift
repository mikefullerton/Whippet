import Foundation

/// Collects activation test results for display in a debug window or log file.
final class ActivationTestLog {
    static let shared = ActivationTestLog()

    private let queue = DispatchQueue(label: "com.mikefullerton.whippet.activation-test-log")
    private(set) var entries: [String] = []

    private init() {}

    func append(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        queue.sync {
            entries.append(line)
        }
        // Also write to a file for easy access
        appendToFile(line)
    }

    func clear() {
        queue.sync { entries.removeAll() }
        clearFile()
    }

    var text: String {
        queue.sync { entries.joined(separator: "\n") }
    }

    // MARK: - File Output

    private static let logURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Whippet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("activation-test.log")
    }()

    private func appendToFile(_ line: String) {
        let url = Self.logURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            handle.closeFile()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func clearFile() {
        try? "".write(to: Self.logURL, atomically: true, encoding: .utf8)
    }

    static var logPath: String { logURL.path }
}
