import SwiftUI

/// The main SwiftUI view displayed inside the floating session palette.
/// Contains the session list on the left and an optional settings drawer on the right.
struct SessionContentView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Session list (left side)
            sessionSide
                .frame(minWidth: 280, idealWidth: 340)

            // Settings drawer (right side, slides in)
            if viewModel.showSettings {
                Divider()

                SettingsDrawerView(viewModel: settingsViewModel) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.showSettings = false
                    }
                }
                .frame(width: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showSettings)
    }

    // MARK: - Session Side

    private var sessionSide: some View {
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
        VStack(spacing: 0) {
            // Compact header
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .opacity(viewModel.activeSessionCount > 0 ? 1 : 0)

                Text("\(viewModel.sessionCount) session\(viewModel.sessionCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if viewModel.activeSessionCount > 0 {
                    Text("\(viewModel.activeSessionCount) active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(viewModel.groups) { group in
                        SessionGroupView(group: group, onSessionClick: viewModel.handleSessionClick)
                    }
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Settings Drawer View

/// A compact single-column settings view for the slide-out drawer.
/// Uses DisclosureGroups so users can expand only the section they need.
struct SettingsDrawerView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    settingsSection("Appearance", image: "paintbrush") {
                        AppearanceSettingsPane(viewModel: viewModel)
                    }
                    settingsSection("General", image: "gearshape") {
                        GeneralSettingsPane(viewModel: viewModel)
                    }
                    settingsSection("Window", image: "macwindow") {
                        WindowSettingsPane(viewModel: viewModel)
                    }
                    settingsSection("Actions", image: "cursorarrow.click") {
                        ActionsSettingsPane(viewModel: viewModel)
                    }
                    settingsSection("Notifications", image: "bell") {
                        NotificationsSettingsPane(viewModel: viewModel)
                    }
                    settingsSection("AI", image: "brain") {
                        AISettingsPane(viewModel: viewModel)
                    }
                    settingsSection("Startup", image: "power") {
                        StartupSettingsPane(viewModel: viewModel)
                    }
                }
                .padding(8)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        image: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            content()
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        } label: {
            Label(title, systemImage: image)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Session Group View

/// A visually separated card showing sessions for a single project.
/// Shows "None" when the project has no active/stale sessions.
struct SessionGroupView: View {
    let group: SessionGroup
    var onSessionClick: ((Session) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Circle()
                    .fill(group.hasActiveSessions ? .green :
                          group.hasStaleSessions ? .orange : .gray.opacity(0.4))
                    .frame(width: 6, height: 6)

                Text(group.projectName)
                    .font(.system(size: 11, weight: .semibold))
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
                    SessionRowView(session: session, onTap: onSessionClick)
                    if session.sessionId != group.sessions.last?.sessionId {
                        Divider()
                            .opacity(0.1)
                            .padding(.leading, 24)
                    }
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
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Primary label: branch, summary, or fallback
                    if !session.gitBranch.isEmpty {
                        Label(session.gitBranch, systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    } else {
                        Text(session.displayLabel)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    if !session.model.isEmpty {
                        Text(abbreviatedModel(session.model))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 6) {
                    // Summary (user prompt) if we have branch + summary
                    if !session.gitBranch.isEmpty && !session.summary.isEmpty {
                        Text(session.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !session.lastTool.isEmpty {
                        Label(session.lastTool, systemImage: "wrench")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(relativeTime(session.lastActivityAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture { onTap?(session) }
    }

    private var statusIndicator: some View {
        Group {
            switch session.status {
            case .active:
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            case .stale:
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
            case .ended:
                Circle()
                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func abbreviatedModel(_ model: String) -> String {
        if model.contains("opus") { return "opus" }
        if model.contains("sonnet") { return "sonnet" }
        if model.contains("haiku") { return "haiku" }
        return model.components(separatedBy: "-").prefix(2).joined(separator: "-")
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
