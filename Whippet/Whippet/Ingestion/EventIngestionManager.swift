import Foundation

/// Watches the drop directory for new JSON event files, parses them, inserts events
/// into the database, creates/updates session records, and deletes consumed files.
/// Malformed files are moved to an `errors/` subdirectory.
final class EventIngestionManager {

    // MARK: - Properties

    /// The directory where hook events are dropped as JSON files.
    let dropDirectoryURL: URL

    /// The subdirectory where malformed JSON files are moved.
    let errorsDirectoryURL: URL

    /// The database manager used to persist events and sessions.
    private let databaseManager: DatabaseManager

    /// File system event stream for watching the drop directory.
    private var eventStream: FSEventStreamRef?

    /// DispatchSource for file-system monitoring (used as primary mechanism).
    private var directorySource: DispatchSourceFileSystemObject?

    /// File descriptor for the monitored directory.
    private var directoryFileDescriptor: Int32 = -1

    /// Queue for processing ingestion work off the main thread.
    private let processingQueue = DispatchQueue(
        label: "com.mikefullerton.whippet.ingestion",
        qos: .userInitiated
    )

    /// Whether the manager is currently running.
    private(set) var isRunning = false

    /// Callback invoked when events are ingested (useful for UI updates).
    var onEventsIngested: (() -> Void)?

    /// Minimum file age (in seconds) before attempting to read it.
    /// This handles the case where a file is still being written.
    static let minimumFileAge: TimeInterval = 0.1

    /// Maximum number of retry attempts for a file that appears to still be written.
    static let maxRetryAttempts = 3

    // MARK: - Initialization

    /// Creates an EventIngestionManager with the given drop directory and database manager.
    /// - Parameters:
    ///   - dropDirectoryURL: The directory to watch for event files. Defaults to `~/.claude/session-events/`.
    ///   - databaseManager: The database manager for persisting events.
    init(dropDirectoryURL: URL? = nil, databaseManager: DatabaseManager) {
        if let url = dropDirectoryURL {
            self.dropDirectoryURL = url
        } else {
            self.dropDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
                .appendingPathComponent("session-events")
        }
        self.errorsDirectoryURL = self.dropDirectoryURL.appendingPathComponent("errors")
        self.databaseManager = databaseManager
    }

    deinit {
        stop()
    }

    // MARK: - Directory Setup

    /// Creates the drop directory and errors subdirectory if they don't exist.
    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dropDirectoryURL.path) {
            try fm.createDirectory(at: dropDirectoryURL, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: errorsDirectoryURL.path) {
            try fm.createDirectory(at: errorsDirectoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Start / Stop

    /// Starts watching the drop directory for new event files.
    /// Creates the directory if it doesn't exist, processes any existing files,
    /// then begins monitoring for new arrivals.
    func start() throws {
        guard !isRunning else { return }

        try ensureDirectoriesExist()

        // Process any files that already exist
        processExistingFiles()

        // Start watching for new files using DispatchSource
        startWatching()

        isRunning = true
        NSLog("Whippet: EventIngestionManager started watching \(dropDirectoryURL.path)")
    }

    /// Stops watching the drop directory.
    func stop() {
        stopWatching()
        isRunning = false
        NSLog("Whippet: EventIngestionManager stopped")
    }

    // MARK: - File System Watching

    private func startWatching() {
        let fd = open(dropDirectoryURL.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Whippet: Failed to open directory for monitoring: \(dropDirectoryURL.path)")
            return
        }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: processingQueue
        )

        source.setEventHandler { [weak self] in
            // Delay slightly to allow files to finish writing and age past minimumFileAge
            self?.processingQueue.asyncAfter(deadline: .now() + Self.minimumFileAge + 0.05) {
                self?.processExistingFiles()
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryFileDescriptor, fd >= 0 {
                close(fd)
                self?.directoryFileDescriptor = -1
            }
        }

        directorySource = source
        source.resume()
    }

    private func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }

    // MARK: - File Processing

    /// Scans the drop directory for JSON files and processes each one.
    func processExistingFiles() {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: dropDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return
        }

        let jsonFiles = contents.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in jsonFiles {
            processFile(at: fileURL)
        }

        if !jsonFiles.isEmpty {
            onEventsIngested?()
        }
    }

    /// Processes a single event JSON file.
    /// - Parameter fileURL: The URL of the JSON file to process.
    func processFile(at fileURL: URL) {
        let fm = FileManager.default

        // Check file age to handle concurrent writes
        if let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
           let modDate = attributes[.modificationDate] as? Date {
            let age = Date().timeIntervalSince(modDate)
            if age < Self.minimumFileAge {
                // File may still be written; skip and retry on next pass
                return
            }
        }

        // Read the file contents
        guard let data = try? Data(contentsOf: fileURL) else {
            NSLog("Whippet: Failed to read file: \(fileURL.lastPathComponent)")
            moveToErrors(fileURL)
            return
        }

        // Ignore empty files (still being written)
        if data.isEmpty {
            return
        }

        // Parse JSON
        guard let eventFile = parseEventFile(data: data, fileName: fileURL.lastPathComponent) else {
            NSLog("Whippet: Malformed JSON in file: \(fileURL.lastPathComponent)")
            moveToErrors(fileURL)
            return
        }

        // Ingest into database
        do {
            try ingestEvent(eventFile, rawData: data)
            // Delete the consumed file
            try fm.removeItem(at: fileURL)
        } catch {
            NSLog("Whippet: Failed to ingest event from \(fileURL.lastPathComponent): \(error.localizedDescription)")
            moveToErrors(fileURL)
        }
    }

    // MARK: - JSON Parsing

    /// Parses an event file's JSON data into an EventFile struct.
    /// Returns nil if the JSON is malformed or missing required fields.
    func parseEventFile(data: Data, fileName: String) -> EventFile? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let event = json["event"] as? String,
              let sessionId = json["session_id"] as? String else {
            return nil
        }

        let timestamp = json["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let eventData = json["data"] as? [String: Any] ?? [:]

        return EventFile(
            event: event,
            sessionId: sessionId,
            timestamp: timestamp,
            data: eventData,
            rawJson: String(data: data, encoding: .utf8) ?? "{}"
        )
    }

    // MARK: - Event Ingestion

    /// Inserts the event into the database and creates/updates the session record.
    func ingestEvent(_ eventFile: EventFile, rawData: Data) throws {
        let rawJson = String(data: rawData, encoding: .utf8) ?? "{}"

        // Create or update the session record
        let session = sessionFromEvent(eventFile)
        try databaseManager.upsertSession(session)

        // Insert the event record
        let event = SessionEvent(
            sessionId: eventFile.sessionId,
            eventType: eventFile.event,
            timestamp: eventFile.timestamp,
            rawJson: rawJson
        )
        try databaseManager.insertEvent(event)

        // If this is a SessionEnd event, mark the session as ended
        if eventFile.event == "SessionEnd" {
            try databaseManager.updateSessionStatus(
                sessionId: eventFile.sessionId,
                status: .ended
            )
        }
    }

    /// Creates a Session model from an event file's data.
    private func sessionFromEvent(_ eventFile: EventFile) -> Session {
        let cwd = eventFile.data["cwd"] as? String ?? ""
        let model = eventFile.data["model"] as? String ?? ""
        let lastTool = eventFile.data["tool"] as? String ?? ""

        let status: SessionStatus = eventFile.event == "SessionEnd" ? .ended : .active

        return Session(
            sessionId: eventFile.sessionId,
            cwd: cwd,
            model: model,
            startedAt: eventFile.event == "SessionStart" ? eventFile.timestamp : "",
            lastActivityAt: eventFile.timestamp,
            lastTool: lastTool,
            status: status
        )
    }

    // MARK: - Error Handling

    /// Moves a file to the errors subdirectory.
    private func moveToErrors(_ fileURL: URL) {
        let fm = FileManager.default
        let destination = errorsDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)

        do {
            try ensureDirectoriesExist()
            // If a file with the same name already exists in errors, remove it first
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: fileURL, to: destination)
            NSLog("Whippet: Moved malformed file to errors: \(fileURL.lastPathComponent)")
        } catch {
            NSLog("Whippet: Failed to move file to errors directory: \(error.localizedDescription)")
            // Last resort: try to delete the problematic file
            try? fm.removeItem(at: fileURL)
        }
    }
}
