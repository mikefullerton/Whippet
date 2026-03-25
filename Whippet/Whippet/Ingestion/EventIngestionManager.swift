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

    /// Callback invoked for each individual event after ingestion, providing the event type,
    /// session ID, and project name. Used by NotificationManager to fire per-event notifications.
    var onEventIngested: ((_ eventType: String, _ sessionId: String, _ projectName: String) -> Void)?

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
        Log.ingestion.info("Started watching \(self.dropDirectoryURL.path, privacy: .public)")
    }

    /// Stops watching the drop directory.
    func stop() {
        stopWatching()
        isRunning = false
        Log.ingestion.info("Stopped")
    }

    // MARK: - File System Watching

    private func startWatching() {
        let fd = open(dropDirectoryURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.ingestion.error("Failed to open directory for monitoring: \(self.dropDirectoryURL.path, privacy: .public)")
            return
        }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: processingQueue
        )

        source.setEventHandler { [weak self] in
            // Coalesce: delay to let files finish writing, then process the whole batch.
            // Suspend the source during processing to avoid re-triggering from our own deletes.
            self?.processingQueue.asyncAfter(deadline: .now() + 0.3) {
                guard let self = self else { return }
                self.directorySource?.suspend()
                self.processExistingFiles()
                self.directorySource?.resume()
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

        if !jsonFiles.isEmpty {
            Log.ingestion.debug("Found \(jsonFiles.count) JSON file(s) to process")
        }

        for fileURL in jsonFiles {
            processFile(at: fileURL)
        }

        if !jsonFiles.isEmpty {
            onEventsIngested?()
            SessionListViewModel.notifySessionsChanged()
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
            Log.ingestion.warning("Failed to read file: \(fileURL.lastPathComponent, privacy: .public)")
            moveToErrors(fileURL)
            return
        }

        // Empty files: if old enough, delete them (failed hook writes).
        // If very recent, skip — the hook may still be writing.
        if data.isEmpty {
            if let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > 5.0 {
                Log.ingestion.debug("Deleting empty file: \(fileURL.lastPathComponent, privacy: .public)")
                try? fm.removeItem(at: fileURL)
            }
            return
        }

        // Parse JSON
        guard let eventFile = parseEventFile(data: data, fileName: fileURL.lastPathComponent) else {
            Log.ingestion.warning("Malformed JSON in file: \(fileURL.lastPathComponent, privacy: .public)")
            moveToErrors(fileURL)
            return
        }

        // Ingest into database
        do {
            try ingestEvent(eventFile, rawData: data)
            // Delete the consumed file
            try fm.removeItem(at: fileURL)
            Log.ingestion.debug("Ingested \(eventFile.event, privacy: .public) for session \(eventFile.sessionId, privacy: .public) from \(fileURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.ingestion.error("Failed to ingest event from \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

        // If this is a UserPromptSubmit event, update the session summary
        if eventFile.event == "UserPromptSubmit", let prompt = eventFile.data["prompt"] as? String, !prompt.isEmpty {
            let truncated = String(prompt.prefix(120))
            try? databaseManager.updateSessionSummary(sessionId: eventFile.sessionId, summary: truncated)
        }

        // If this is a SessionEnd event, mark the session as ended
        if eventFile.event == "SessionEnd" {
            try databaseManager.updateSessionStatus(
                sessionId: eventFile.sessionId,
                status: .ended
            )
        }

        // Notify per-event callback (used for notifications)
        let projectName = session.projectName
        onEventIngested?(eventFile.event, eventFile.sessionId, projectName)
    }

    /// Creates a Session model from an event file's data.
    private func sessionFromEvent(_ eventFile: EventFile) -> Session {
        let cwd = eventFile.data["cwd"] as? String ?? ""
        let model = eventFile.data["model"] as? String ?? ""
        let lastTool = eventFile.data["tool"] as? String ?? ""
        let gitBranch = cwd.isEmpty ? "" : GitMetadataResolver.shared.resolveBranch(cwd: cwd)

        let status: SessionStatus = eventFile.event == "SessionEnd" ? .ended : .active

        return Session(
            sessionId: eventFile.sessionId,
            cwd: cwd,
            model: model,
            startedAt: eventFile.event == "SessionStart" ? eventFile.timestamp : "",
            lastActivityAt: eventFile.timestamp,
            lastTool: lastTool,
            status: status,
            gitBranch: gitBranch
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
            Log.ingestion.info("Moved malformed file to errors/: \(fileURL.lastPathComponent, privacy: .public)")
        } catch {
            Log.ingestion.error("Failed to move file to errors directory: \(error.localizedDescription, privacy: .public)")
            // Last resort: try to delete the problematic file
            try? fm.removeItem(at: fileURL)
        }
    }
}
