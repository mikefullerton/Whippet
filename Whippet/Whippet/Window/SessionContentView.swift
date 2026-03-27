import SwiftUI

/// The main SwiftUI view displayed inside the floating session palette.
struct SessionContentView: View {
    @ObservedObject var viewModel: SessionListViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isEmpty {
                emptyState
            } else {
                sessionList
            }

            // Error banner for failed click actions
            if let error = viewModel.lastActionError {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.lastPermissionPane != nil
                              ? "lock.shield" : "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.system(size: 11))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    if viewModel.lastPermissionPane != nil {
                        Button(action: { viewModel.openPermissionSettings() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Open System Settings")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(viewModel.lastPermissionPane != nil
                            ? Color.orange.opacity(0.15)
                            : Color.red.opacity(0.15))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.lastActionError)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dog.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text("No Active Sessions")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.groups) { group in
                SessionGroupView(
                    group: group,
                    onSessionClick: viewModel.handleSessionClick,
                    summarizingSessionIds: viewModel.summarizingSessionIds,
                    onSummarize: viewModel.summarizeSession,
                    frontmostSessionId: viewModel.frontmostSessionId
                )
            }
        }
        .padding(8)
    }
}

// MARK: - Session Group View

/// A visually separated card showing sessions for a single project.
/// Shows "None" when the project has no active/stale sessions.
struct SessionGroupView: View {
    let group: SessionGroup
    var onSessionClick: ((Session) -> Void)?
    var summarizingSessionIds: Set<String> = []
    var onSummarize: ((Session) -> Void)?
    var frontmostSessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Text(group.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !group.abbreviatedPath.isEmpty {
                    Text(group.abbreviatedPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().opacity(0.15)

            // Sessions
            if group.sessions.isEmpty {
                Text("None")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                ForEach(group.sessions, id: \.sessionId) { session in
                    SessionRowView(
                        session: session,
                        onTap: onSessionClick,
                        isSummarizing: summarizingSessionIds.contains(session.sessionId),
                        onSummarize: onSummarize,
                        isFrontmost: session.sessionId == frontmostSessionId
                    )
                    Divider().opacity(0.15)
                }
            }
        }
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: Session
    var onTap: ((Session) -> Void)?
    var isSummarizing: Bool = false
    var onSummarize: ((Session) -> Void)?
    var isFrontmost: Bool = false

    var body: some View {
        Button { onTap?(session) } label: {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(isFrontmost ? Color.blue : Color.clear)
                    .frame(width: 6, height: 6)

                if isSummarizing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Summarizing...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(session.displayLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Text(relativeTime(session.lastActivityAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(SessionRowButtonStyle())
        .contextMenu {
            Button("Summarize with AI") {
                onSummarize?(session)
            }
            .disabled(isSummarizing)
        }
    }

    private func relativeTime(_ timestamp: String) -> String {
        guard !timestamp.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestamp) {
            return relativeTimeFromDate(date)
        }
        formatter.formatOptions.remove(.withFractionalSeconds)
        if let date = formatter.date(from: timestamp) {
            return relativeTimeFromDate(date)
        }
        return ""
    }

    private func relativeTimeFromDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

// MARK: - Session Row Button Style

/// A button style that provides hover and press feedback for session rows.
struct SessionRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.white.opacity(0.12)
                    : isHovered ? Color.white.opacity(0.06) : Color.clear
            )
            .onHover { isHovered = $0 }
    }
}
