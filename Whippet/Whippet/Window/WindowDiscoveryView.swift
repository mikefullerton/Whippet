import SwiftUI

/// A floating panel view that shows all discoverable windows grouped by app.
/// Opens immediately with a spinner while window enumeration runs asynchronously.
struct WindowDiscoveryView: View {
    @ObservedObject var viewModel: WindowDiscoveryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.isLoading {
                loadingState
            } else if viewModel.accessibilityDenied {
                accessibilityDeniedState
            } else if viewModel.apps.isEmpty {
                emptyState
            } else {
                windowList
            }
        }
        .frame(minWidth: 340, idealWidth: 380, minHeight: 200, idealHeight: 420, maxHeight: 600)
        .onAppear {
            viewModel.discoverWindows()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Select Window")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(viewModel.session.projectName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Discovering windows\u{2026}")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Accessibility Denied

    private var accessibilityDeniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Accessibility Access Required")
                .font(.system(size: 12, weight: .medium))
            Text("Grant Whippet Accessibility access to discover and activate windows.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Open System Settings") {
                viewModel.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No windows found")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Window List

    private var windowList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(viewModel.apps) { app in
                    DiscoveredAppSection(
                        app: app,
                        onWindowSelected: viewModel.activateWindow
                    )
                }
            }
            .padding(8)
        }
    }
}

// MARK: - App Section

/// A collapsible section showing an app and its windows.
struct DiscoveredAppSection: View {
    let app: DiscoveredApp
    let onWindowSelected: (DiscoveredWindow) -> Void
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // App header
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app")
                            .frame(width: 16, height: 16)
                    }

                    Text(app.name)
                        .font(.system(size: 11, weight: .semibold))

                    Text("(\(app.windows.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(app.windows) { window in
                    DiscoveredWindowRow(window: window, onSelected: onWindowSelected)
                }
            }
        }
        .background(app.hasMatch ? Color.accentColor.opacity(0.06) : Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(app.hasMatch ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
    }
}

// MARK: - Window Row

/// A single discoverable window. Highlighted if it matches the session's project name.
struct DiscoveredWindowRow: View {
    let window: DiscoveredWindow
    let onSelected: (DiscoveredWindow) -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelected(window) }) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(window.isMatch ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(window.title)
                    .font(.system(size: 11, weight: window.isMatch ? .medium : .regular))
                    .foregroundStyle(window.isMatch ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if window.isMatch {
                    Text("match")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 8)
            .padding(.leading, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
    }
}
