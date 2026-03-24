import SwiftUI

/// The settings window SwiftUI content view. Organized into sections:
/// General (staleness timeout), Window (always-on-top, transparency),
/// Notifications (per-event-type toggles), and Actions (click action picker,
/// custom command template).
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            generalSection
            windowSection
            notificationsSection
            actionsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 400)
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Staleness Timeout")
                    Spacer()
                    Text(viewModel.stalenessTimeoutDisplay)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $viewModel.stalenessTimeout,
                    in: 30...600,
                    step: 10
                )

                Text("Sessions with no events within this timeout are marked as stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("General", systemImage: "gearshape")
        }
    }

    // MARK: - Window Section

    private var windowSection: some View {
        Section {
            Toggle("Always on Top", isOn: $viewModel.alwaysOnTop)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window Transparency")
                    Spacer()
                    Text("\(Int(viewModel.transparency * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $viewModel.transparency,
                    in: 0.3...1.0,
                    step: 0.05
                )
            }
        } header: {
            Label("Window", systemImage: "macwindow")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle("Session Started", isOn: $viewModel.notifySessionStart)
            Toggle("Session Ended", isOn: $viewModel.notifySessionEnd)
            Toggle("Session Became Stale", isOn: $viewModel.notifyStale)

            Text("Notifications require permission. macOS will prompt you on first use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Notifications", systemImage: "bell")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            Picker("Click Action", selection: $viewModel.clickAction) {
                ForEach(SessionClickAction.allCases, id: \.self) { action in
                    Label(action.displayName, systemImage: action.systemImage)
                        .tag(action)
                }
            }

            if viewModel.clickAction == .customCommand {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shell Command Template")
                        .font(.subheadline)

                    TextField("Command...", text: $viewModel.customCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Available variables: $SESSION_ID, $CWD, $MODEL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Actions", systemImage: "cursorarrow.click")
        }
    }
}
