import SwiftUI

/// The main SwiftUI view displayed inside the floating session panel.
///
/// Shows sessions grouped by project with collapsible sections, real-time updates,
/// and visual status indicators. Displays an empty state when no sessions exist.
struct SessionContentView: View {
    @ObservedObject var viewModel: SessionListViewModel

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dog.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Sessions")
                .font(.headline)

            Text("Start a Claude Code session to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            // Header
            sessionListHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Grouped session list
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.groups) { group in
                        SessionGroupView(group: group)
                    }
                }
            }
        }
    }

    private var sessionListHeader: some View {
        HStack {
            Text("\(viewModel.sessionCount) session\(viewModel.sessionCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.activeSessionCount > 0 {
                Text("\(viewModel.activeSessionCount) active")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }

            Spacer()
        }
    }
}

// MARK: - Session Group View

/// A collapsible section showing sessions for a single project.
struct SessionGroupView: View {
    let group: SessionGroup
    @State private var isExpanded = true

    var body: some View {
        Section {
            if isExpanded {
                ForEach(group.sessions, id: \.sessionId) { session in
                    SessionRowView(session: session)
                    if session.sessionId != group.sessions.last?.sessionId {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        } header: {
            groupHeader
        }
    }

    private var groupHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                if group.hasActiveSessions {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }

                Text(group.projectName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("(\(group.sessions.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row View

/// Displays a single session with its status, metadata, and activity information.
struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIndicator
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                // Top line: working directory and model
                HStack {
                    Text(session.cwd.isEmpty ? "Unknown" : abbreviatedPath(session.cwd))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if !session.model.isEmpty {
                        Text(session.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Bottom line: timestamps and last tool
                HStack(spacing: 8) {
                    Label(formatTimestamp(session.startedAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !session.lastTool.isEmpty {
                        Label(session.lastTool, systemImage: "wrench")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(relativeTime(session.lastActivityAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Group {
            switch session.status {
            case .active:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            case .stale:
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            case .ended:
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Abbreviates a file path by replacing the home directory with ~.
    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Formats an ISO 8601 timestamp into a short time string.
    private func formatTimestamp(_ timestamp: String) -> String {
        guard !timestamp.isEmpty else { return "Unknown" }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            // Try without fractional seconds
            formatter.formatOptions.remove(.withFractionalSeconds)
            guard let date = formatter.date(from: timestamp) else {
                return timestamp
            }
            return formatDate(date)
        }
        return formatDate(date)
    }

    /// Formats a Date into a human-readable time.
    private func formatDate(_ date: Date) -> String {
        let displayFormatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            displayFormatter.dateFormat = "h:mm a"
        } else {
            displayFormatter.dateFormat = "MMM d, h:mm a"
        }
        return displayFormatter.string(from: date)
    }

    /// Returns a relative time string like "2m ago" or "1h ago".
    private func relativeTime(_ timestamp: String) -> String {
        guard !timestamp.isEmpty else { return "" }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: timestamp) else {
            formatter.formatOptions.remove(.withFractionalSeconds)
            guard let date = formatter.date(from: timestamp) else {
                return ""
            }
            return relativeTimeFromDate(date)
        }
        return relativeTimeFromDate(date)
    }

    private func relativeTimeFromDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
