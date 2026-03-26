import AppKit
import Combine

/// A single window discovered via the Accessibility API.
struct DiscoveredWindow: Identifiable {
    let id: Int
    let title: String
    let pid: pid_t
    let axElement: AXUIElement
    /// Whether this window's title matches the session's project name.
    let isMatch: Bool
}

/// A running application and its discoverable windows.
struct DiscoveredApp: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let windows: [DiscoveredWindow]
    /// Whether any window in this app matches the session.
    var hasMatch: Bool { windows.contains { $0.isMatch } }
}

/// Discovers all on-screen windows using the Accessibility API and groups them by app.
/// Does not require Screen Recording permission — only Accessibility.
final class WindowDiscoveryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isLoading = true
    @Published var apps: [DiscoveredApp] = []
    @Published var accessibilityDenied = false

    // MARK: - Properties

    let session: Session

    /// Called after the user selects and activates a window so the panel can close.
    var onWindowActivated: (() -> Void)?

    // MARK: - Initialization

    init(session: Session) {
        self.session = session
    }

    // MARK: - Discovery

    /// Snapshot of a running application's metadata, captured on the main thread.
    private struct AppSnapshot {
        let pid: pid_t
        let name: String
        let icon: NSImage?
    }

    /// Enumerates all windows asynchronously. Call from onAppear.
    func discoverWindows() {
        isLoading = true
        accessibilityDenied = false

        guard AXIsProcessTrusted() else {
            isLoading = false
            accessibilityDenied = true
            return
        }

        // Snapshot app metadata on the main thread (NSWorkspace/NSRunningApplication are main-thread APIs)
        let appSnapshots: [AppSnapshot] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular else { return nil }
            return AppSnapshot(pid: app.processIdentifier, name: app.localizedName ?? "Unknown", icon: app.icon)
        }
        let projectName = session.projectName

        // AX enumeration on a background thread — this is the slow part
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let results = self.enumerateWindows(for: appSnapshots, matching: projectName)
            DispatchQueue.main.async {
                self.apps = results
                self.isLoading = false
            }
        }
    }

    /// Queries the Accessibility API for each snapshotted app's windows.
    /// Safe to call from any thread — only uses AX C API and the pre-captured snapshots.
    private func enumerateWindows(for snapshots: [AppSnapshot], matching projectName: String) -> [DiscoveredApp] {
        var result: [DiscoveredApp] = []

        for app in snapshots {
            let axApp = AXUIElementCreateApplication(app.pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            var windows: [DiscoveredWindow] = []
            for (i, axWindow) in axWindows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""

                // Skip windows with empty titles (menus, toolbars, popups)
                guard !title.isEmpty else { continue }

                let isMatch = !projectName.isEmpty
                    && projectName != "Unknown"
                    && title.localizedCaseInsensitiveContains(projectName)

                windows.append(DiscoveredWindow(
                    id: Int(app.pid) * 10000 + i,
                    title: title,
                    pid: app.pid,
                    axElement: axWindow,
                    isMatch: isMatch
                ))
            }

            guard !windows.isEmpty else { continue }

            result.append(DiscoveredApp(
                id: app.pid,
                name: app.name,
                icon: app.icon,
                windows: windows
            ))
        }

        // Sort: apps with matches first, then alphabetical
        return result.sorted { lhs, rhs in
            if lhs.hasMatch != rhs.hasMatch { return lhs.hasMatch }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Activation

    /// Activates the selected window and its owning app.
    func activateWindow(_ window: DiscoveredWindow) {
        Log.actions.info("WindowDiscovery: activating '\(window.title, privacy: .public)' (PID \(window.pid))")
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        onWindowActivated?()
    }

    func openAccessibilitySettings() {
        PermissionPane.accessibility.open()
    }
}
