import SwiftUI

enum SettingsTopic: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case general = "General"
    case window = "Window"
    case actions = "Actions"
    case notifications = "Notifications"
    case ai = "AI"
    case startup = "Startup"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appearance: return "paintbrush"
        case .general: return "gearshape"
        case .window: return "macwindow"
        case .actions: return "cursorarrow.click"
        case .notifications: return "bell"
        case .ai: return "brain"
        case .startup: return "power"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTopic: SettingsTopic = .appearance

    var body: some View {
        NavigationSplitView {
            List(SettingsTopic.allCases, selection: $selectedTopic) { topic in
                Label(topic.rawValue, systemImage: topic.systemImage)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            ScrollView {
                detailContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 550, minHeight: 420)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTopic {
        case .appearance: AppearanceSettingsPane(viewModel: viewModel)
        case .general: GeneralSettingsPane(viewModel: viewModel)
        case .window: WindowSettingsPane(viewModel: viewModel)
        case .actions: ActionsSettingsPane(viewModel: viewModel)
        case .notifications: NotificationsSettingsPane(viewModel: viewModel)
        case .ai: AISettingsPane(viewModel: viewModel)
        case .startup: StartupSettingsPane(viewModel: viewModel)
        }
    }
}

// MARK: - Appearance Settings Pane

struct AppearanceSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section: Appearance Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.headline)

                Picker("", selection: $viewModel.appearanceMode) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto (System)").tag("auto")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            // Section: Text Size
            VStack(alignment: .leading, spacing: 8) {
                Text("Text Size")
                    .font(.headline)

                HStack(spacing: 12) {
                    Text("A")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 2) {
                        Slider(value: $viewModel.textSize, in: -4...4, step: 1)

                        // "Default" label centered under the slider at the 0 mark
                        GeometryReader { geo in
                            Text("Default")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .position(x: geo.size.width * 0.5, y: 0)
                                .opacity(abs(viewModel.textSize) < 0.5 ? 1 : 0.3)
                        }
                        .frame(height: 12)
                    }

                    Text("A")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }

                // Preview
                Text("Example")
                    .font(.system(size: max(9, 13 + viewModel.textSize)))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - General Settings Pane

struct GeneralSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Staleness Timeout")
                    .font(.headline)

                HStack {
                    Slider(
                        value: $viewModel.stalenessTimeout,
                        in: 30...600,
                        step: 10
                    )
                    Text(viewModel.stalenessTimeoutDisplay)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 80, alignment: .trailing)
                }

                Text("Sessions with no events within this timeout are marked as stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Window Settings Pane

struct WindowSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Window Behavior")
                    .font(.headline)

                Toggle("Always on Top", isOn: $viewModel.alwaysOnTop)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Transparency")
                    .font(.headline)

                HStack {
                    Slider(
                        value: $viewModel.transparency,
                        in: 0.3...1.0,
                        step: 0.05
                    )
                    Text("\(Int(viewModel.transparency * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Actions Settings Pane

struct ActionsSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Click Action")
                    .font(.headline)

                Picker("Click Action", selection: $viewModel.clickAction) {
                    ForEach(SessionClickAction.allCases, id: \.self) { action in
                        Label(action.displayName, systemImage: action.systemImage)
                            .tag(action)
                    }
                }
                .labelsHidden()
            }

            if viewModel.clickAction == .customCommand {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shell Command Template")
                        .font(.headline)

                    TextField("Command...", text: $viewModel.customCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Available variables: $SESSION_ID, $CWD, $MODEL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Notifications Settings Pane

struct NotificationsSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notify When")
                    .font(.headline)

                Toggle("Session Started", isOn: $viewModel.notifySessionStart)
                Toggle("Session Ended", isOn: $viewModel.notifySessionEnd)
                Toggle("Session Became Stale", isOn: $viewModel.notifyStale)
            }

            Text("Notifications require permission. macOS will prompt you on first use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI Settings Pane

struct AISettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enable toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Summaries")
                    .font(.headline)

                Toggle("Enable AI session summaries", isOn: $viewModel.aiSummariesEnabled)

                Text("Uses AI to generate a short description of what each session is doing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Provider selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.headline)

                Picker("Provider", selection: $viewModel.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
            }

            // Model selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.headline)

                if viewModel.aiProvider.defaultModels.isEmpty {
                    TextField("Model name", text: $viewModel.aiModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Picker("Model", selection: $viewModel.aiModel) {
                        ForEach(viewModel.aiProvider.defaultModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()

                    TextField("Or type a model name", text: $viewModel.aiModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                // Recommended model hint
                if !viewModel.aiProvider.recommendedNote.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text("Recommended: \(viewModel.aiProvider.recommendedNote)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.aiModel != viewModel.aiProvider.recommendedModel {
                        Button("Use recommended") {
                            viewModel.aiModel = viewModel.aiProvider.recommendedModel
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }

            Divider()

            // API Key
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.headline)

                SecureField(viewModel.aiProvider.apiKeyPlaceholder, text: $viewModel.aiAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            // Custom base URL (only for custom provider)
            if viewModel.aiProvider == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Base URL")
                        .font(.headline)

                    TextField("https://api.example.com", text: $viewModel.aiBaseURL)
                        .textFieldStyle(.roundedBorder)

                    Text("OpenAI-compatible API endpoint. Must support /v1/chat/completions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Startup Settings Pane

struct StartupSettingsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Launch at Login")
                    .font(.headline)

                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

                if viewModel.shouldShowLaunchAtLoginPrompt {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Whippet works best when it starts automatically with your Mac. Enable launch at login so you never miss a Claude Code session.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Got It") {
                            viewModel.dismissLaunchAtLoginPrompt()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }

                Text("Requires the app to be in /Applications or have a valid bundle identifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
