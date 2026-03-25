import Foundation
import os

/// Centralized OSLog loggers for Whippet, organized by subsystem category.
///
/// Usage: `Log.database.info("Opened database at \(path)")`
///
/// All loggers share the bundle identifier as their subsystem so they can be
/// filtered together in Console.app with:
///   `log stream --predicate 'subsystem == "com.mikefullerton.Whippet"'`
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mikefullerton.Whippet"

    /// App lifecycle: launch, setup, teardown.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// SQLite database: open, close, migrations, CRUD operations.
    static let database = Logger(subsystem: subsystem, category: "database")

    /// Event ingestion: file watching, parsing, processing.
    static let ingestion = Logger(subsystem: subsystem, category: "ingestion")

    /// Hook installation and management.
    static let hooks = Logger(subsystem: subsystem, category: "hooks")

    /// Session liveness detection and staleness marking.
    static let liveness = Logger(subsystem: subsystem, category: "liveness")

    /// macOS user notifications.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// Click actions: terminal, transcript, clipboard, custom command.
    static let actions = Logger(subsystem: subsystem, category: "actions")

    /// Floating panel window and session list UI.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Settings and preferences.
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// AI-related operations.
    static let ai = Logger(subsystem: subsystem, category: "ai")
}
