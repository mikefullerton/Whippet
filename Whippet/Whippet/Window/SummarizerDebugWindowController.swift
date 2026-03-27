import AppKit
import SwiftUI
import Combine

/// In-memory log of summarizer activity, displayed in a debug window.
final class SummarizerDebugLog: ObservableObject {
    static let shared = SummarizerDebugLog()

    @Published private(set) var entries: [String] = []

    func append(_ message: String) {
        let ts = Self.timestampFormatter.string(from: Date())
        let line = "[\(ts)] \(message)"
        if Thread.isMainThread {
            entries.append(line)
        } else {
            DispatchQueue.main.async { self.entries.append(line) }
        }
    }

    func clear() {
        entries.removeAll()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// SwiftUI view showing the scrolling debug transcript.
struct SummarizerDebugView: View {
    @ObservedObject var log = SummarizerDebugLog.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Summarizer Debug Log")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(log.entries.count) entries")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Clear") { log.clear() }
                    .font(.system(size: 11))
            }
            .padding(8)

            Divider()

            if log.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("No summarizer activity yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Trigger a session end or right-click a session and choose \"Summarize with AI\".")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.entries.enumerated()), id: \.offset) { idx, entry in
                                Text(entry)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .id(idx)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: log.entries.count) {
                        if let last = log.entries.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

/// AppKit window controller for the debug log.
final class SummarizerDebugWindowController {
    private var window: NSWindow?

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SummarizerDebugView()
        let hostingView = NSHostingView(rootView: view)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Summarizer Debug Log"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = w
    }
}
