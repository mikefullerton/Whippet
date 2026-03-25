---
id: "roadmap-create-app-001"
created: "2026-03-24"
modified: "2026-03-24"
author: "mikefullerton"
change-history:
  - date: "2026-03-24"
    description: "Initial draft"
---

# Feature Roadmap: CreateApp (Whippet)

# Feature Definition: CreateApp (Whippet)

## Goal and Purpose

Build **Whippet**, a standalone macOS menu bar app that monitors all active Claude Code sessions in real time. It provides a floating window showing sessions grouped by project, with configurable click actions, notifications, and always-on behavior. It consumes session events produced by Claude Code global hooks via a file-based event queue.

## Platform / Component

macOS desktop application (standalone, separate repo at `~/projects/Whippet`).

## Tools and Technologies

- [x] Swift / macOS SDK (AppKit + SwiftUI)
- [x] NSPanel (floating window with configurable level and transparency)
- [x] NSHostingController / NSHostingView (SwiftUI hosted in AppKit)
- [x] NSStatusItem (menu bar presence)
- [x] SQLite3 (built-in macOS C API with Swift wrapper, or GRDB.swift)
- [x] FSEvents / DispatchSource (file system watching)
- [x] UNUserNotificationCenter (macOS notifications)
- [x] SMAppService (launch at login)
- [x] Claude Code global hooks (event producers)

## External Resources

- Claude Code hooks documentation: https://docs.anthropic.com/en/docs/claude-code/hooks
- SMAppService documentation: https://developer.apple.com/documentation/servicemanagement/smappservice
- FSEvents API: https://developer.apple.com/documentation/coreservices/file_system_events

## Extended Description

### Overview

Whippet is a lightweight macOS app that lives in the menu bar and provides a real-time view of all Claude Code sessions running on the machine. It works by:

1. **Auto-installing Claude Code hooks** on first launch that write one JSON file per hook event to a drop directory (`~/.claude/session-events/`).
2. **Watching the drop directory** via FSEvents, consuming each JSON file, inserting the event into a local SQLite database, and deleting the file.
3. **Displaying a floating window** (NSPanel) with a SwiftUI-based list of active sessions grouped by repository/project.
4. **Supporting configurable click actions** on sessions: open terminal, open transcript, copy session ID, run a custom shell command, or send a notification.

### Event Pipeline

- **Hooks → Drop Directory**: Each Claude Code hook event writes a single JSON file to `~/.claude/session-events/` named `{timestamp}-{uuid}.json`. The JSON contains the event type, session ID, timestamp, and event-specific data.
- **Drop Directory → SQLite**: Whippet watches the directory, reads each file, inserts the event into SQLite, and deletes the file. The drop file acts as a lightweight queue; SQLite is the source of truth.

### Session Display

Each session row shows:
- Working directory (and derived project/repo name for grouping)
- Model name
- Time started
- Last activity timestamp
- Last tool used
- Status: Active / Stale / Ended

Sessions are grouped by repository/project.

### Staleness Detection

A configurable timer (default: 1 minute) marks sessions as stale if no events arrive within the timeout period. This handles cases where Claude crashes without firing `SessionEnd`.

### Settings

Configurable via a settings window:
- Staleness timeout duration
- Always-on-top toggle (default: on)
- Window transparency level
- Notification preferences per event type (SessionStart, SessionEnd, Stale)
- Click action selection (from the set of supported actions)

### Launch at Login

Uses `SMAppService` to register for launch at login, with proper permission request flow on first launch.

## Acceptance Criteria

- [ ] App runs as a menu bar app with no dock icon (LSUIElement)
- [ ] Floating window displays active Claude sessions grouped by repository/project
- [ ] Sessions show: working directory, model, time started, last activity, last tool used, status
- [ ] Hook events are consumed from the drop directory and ingested into SQLite
- [ ] Consumed event files are deleted after ingestion
- [ ] Hooks are auto-installed into `~/.claude/settings.json` on first launch
- [ ] Clicking a session triggers the configured action
- [ ] All five click actions work: open terminal, open transcript, copy session ID, custom shell command, notification
- [ ] Settings window allows configuring: staleness timeout, always-on-top, transparency, notifications, click action
- [ ] Stale sessions are detected and marked after configurable timeout
- [ ] macOS notifications fire for configured event types
- [ ] Launch at login works with proper permission handling
- [ ] App handles edge cases: missing drop directory, malformed JSON files, concurrent writes

## Dependencies / Prerequisites

- User creates the `~/projects/Whippet` repository before implementation begins
- Claude Code installed on the machine (for hooks to function)
- macOS 14+ (for SMAppService and modern SwiftUI features)

## Risks and Unknowns

- **High event volume**: A busy session could produce 30-50 tool-use events per minute. FSEvents + file deletion must keep up.
- **Hook installation conflicts**: If the user already has hooks in `~/.claude/settings.json`, auto-installation must merge, not overwrite.
- **Stale session false positives**: 1-minute default might be too aggressive if a user is just reading Claude's output. May need tuning.
- **Multiple Claude Code versions**: Hook payload format could change between versions.

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Event transport | File-based drop directory (one file per event) | Hooks are shell commands; writing a file is simpler and more reliable than SQLite from bash |
| Data storage | SQLite | Structured queries, no log rotation needed, built into macOS |
| Window system | NSPanel + NSHostingController | NSPanel gives control over window level/transparency; NSHostingController bridges to SwiftUI |
| Menu bar | NSStatusItem | Full AppKit control over menu bar behavior |
| App lifecycle | LSUIElement + SMAppService | No dock icon; proper launch-at-login |

## Related Features / Issues

- Claude Code hooks system (reference memory saved this session)
- Catnip IDE (scratching-post) — sibling project in the cat-themed tool family

## Verification Strategy

| Check | Command / Approach |
|-------|-------------------|
| Build | `xcodebuild -scheme Whippet -configuration Debug build` |
| Test | `xcodebuild -scheme Whippet -configuration Debug test` |
| Local verification | Launch app, start a Claude Code session, verify session appears in floating window. Click session, verify action fires. Change settings, verify behavior updates. |
| Manual verification flags | Verify hook auto-installation doesn't corrupt existing hooks. Verify launch at login permission prompt appears correctly. Verify stale detection with killed sessions. |


## Change History

_Populated automatically by /implement-roadmap when the feature is complete._

### Commits

| Hash | Description |
|------|-------------|

### Issues

| Issue | Title |
|-------|-------|

### Pull Request

_N/A — predates Change History feature_

## Deviations from Plan

_Filled in at completion — what changed from the original plan and why._


## Platform & Tools Summary

macOS app using Swift, AppKit (NSPanel, NSStatusItem, NSHostingController), SwiftUI, SQLite, FSEvents, UNUserNotificationCenter, and SMAppService. Consumes Claude Code hook events via a file-based drop directory.

## Progress

| Total Steps | Complete | In Progress | Blocked | Not Started |
|-------------|----------|-------------|---------|-------------|
| 12          | 11       | 0           | 0       | 1           |

## Implementation Steps

### Step 1: Project Scaffold & Menu Bar Shell

- **GitHub Issue**: #2
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: None (user must have created `~/projects/Whippet` repo)
- **Acceptance Criteria**:
  - [x] Xcode project created with Swift, macOS target
  - [x] `LSUIElement` set to `YES` in Info.plist (no dock icon)
  - [x] AppDelegate creates an `NSStatusItem` with a placeholder icon in the menu bar
  - [x] Menu bar dropdown has "Show Sessions", "Settings", and "Quit" items
  - [x] App launches and shows the menu bar icon with no crashes
- **Testing / Verification**:
  - [x] Build succeeds with `xcodebuild`
  - [x] Launch app, verify menu bar icon appears
  - [x] Click menu items, verify they respond (can be no-ops for now)
- **PR**: _TBD_
- **Notes**: Used AppDelegate-based lifecycle with `@main` attribute. Menu bar icon uses SF Symbol `dog.fill`.

---

### Step 2: SQLite Database Layer

- **GitHub Issue**: #3
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Step 1
- **Acceptance Criteria**:
  - [x] SQLite database created at `~/Library/Application Support/Whippet/whippet.db`
  - [x] Schema includes tables: `sessions`, `events`, `settings`
  - [x] `sessions` table: id, session_id, cwd, model, started_at, last_activity_at, last_tool, status (active/stale/ended)
  - [x] `events` table: id, session_id, event_type, timestamp, raw_json
  - [x] `settings` table: key-value store for app configuration
  - [x] Swift wrapper with CRUD operations for all tables
  - [x] Database migrations support for future schema changes
- **Testing / Verification**:
  - [x] Unit tests for all CRUD operations
  - [x] Verify database file is created on first launch
  - [x] Verify schema matches specification
- **PR**: _TBD_
- **Notes**: Used SQLite3 C API with a thin Swift wrapper (DatabaseManager). WAL mode enabled for concurrent read performance. Migration system uses schema_migrations table. 23 unit tests covering all CRUD operations, schema validation, upsert behavior, and migration idempotency.

---

### Step 3: Drop Directory & Event Ingestion

- **GitHub Issue**: #4
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Step 2
- **Acceptance Criteria**:
  - [x] App creates `~/.claude/session-events/` on launch if it doesn't exist
  - [x] FSEvents or DispatchSource watches the directory for new files
  - [x] New `.json` files are read, parsed, and inserted into the `events` table
  - [x] Session records in `sessions` table are created/updated based on events
  - [x] Consumed files are deleted after successful ingestion
  - [x] Malformed JSON files are logged and moved to an `errors/` subdirectory
  - [x] Handles concurrent file writes gracefully (file not yet fully written)
- **Testing / Verification**:
  - [x] Unit tests for JSON parsing of all event types
  - [x] Integration test: drop a JSON file, verify it appears in the database and the file is deleted
  - [x] Stress test: drop 50 files rapidly, verify all are consumed
- **PR**: _TBD_
- **Notes**: Uses DispatchSource file system monitoring with a brief delay (minimumFileAge + 50ms) to handle concurrent writes. EventIngestionManager processes files on a dedicated background queue. 30 tests covering all event types, error handling, and stress scenarios.

---

### Step 4: Hook Auto-Installation

- **GitHub Issue**: #5
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Step 3
- **Acceptance Criteria**:
  - [x] On first launch, app reads `~/.claude/settings.json` (or creates it if missing)
  - [x] Installs hooks for: SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop, Notification
  - [x] Each hook writes a JSON file to `~/.claude/session-events/` with event type, session ID, timestamp, and relevant payload
  - [x] Existing hooks in `settings.json` are preserved (merge, not overwrite)
  - [x] App detects if its hooks are already installed and skips re-installation
  - [x] Hook commands use portable shell syntax (no bash-specific features)
- **Testing / Verification**:
  - [x] Test with empty `settings.json` — hooks are installed correctly
  - [x] Test with existing hooks — Whippet hooks are appended, existing hooks untouched
  - [x] Test with Whippet hooks already present — no duplicates created
  - [x] Verify generated hook commands produce valid JSON files
- **PR**: _TBD_
- **Notes**: HookInstaller uses a `# whippet-hook` marker comment in each command to identify Whippet hooks for detection and uninstallation. Each hook command reads the Claude Code JSON payload from stdin, pipes it through `jq` to extract event-specific fields, and writes a JSON file to the drop directory. Supports uninstallation to cleanly remove hooks. 29 unit tests covering all scenarios.

---

### Step 5: Floating Window Shell (NSPanel)

- **GitHub Issue**: #6
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Step 1
- **Acceptance Criteria**:
  - [x] NSPanel created with `.floating` window level (default)
  - [x] Window level is configurable (floating vs normal)
  - [x] Window has configurable transparency (alpha value)
  - [x] SwiftUI content hosted via NSHostingController
  - [x] Panel toggles visibility from the menu bar "Show Sessions" item
  - [x] Panel remembers its position between toggles
  - [x] Panel has a clean, minimal chrome appropriate for a utility window
- **Testing / Verification**:
  - [x] Launch app, toggle panel from menu bar — appears and disappears
  - [x] Verify panel floats above other windows when set to floating
  - [x] Verify transparency is adjustable
  - [x] Move panel, hide, show — verify position is remembered
- **PR**: _TBD_
- **Notes**: SessionPanel (NSPanel subclass) with `.utilityWindow` and `.nonactivatingPanel` style masks. SessionPanelController manages lazy creation, visibility toggle, position persistence via savedOrigin and frame autosave, and configurable floating/normal level and transparency (clamped 0.3-1.0). SwiftUI placeholder content via NSHostingController. 28 unit tests covering all acceptance criteria.

---

### Step 6: Session List UI

- **GitHub Issue**: #7
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Steps 2, 3, 5
- **Acceptance Criteria**:
  - [x] SwiftUI view displays sessions from SQLite database
  - [x] Sessions are grouped by repository/project (derived from working directory)
  - [x] Each session row shows: working directory, model, time started, last activity, last tool used, status
  - [x] Active sessions have a visual indicator distinct from stale and ended sessions
  - [x] List updates in real time as new events are ingested
  - [x] Empty state shown when no sessions exist
  - [x] Groups are collapsible
- **Testing / Verification**:
  - [x] Insert test session data into database, verify UI renders correctly
  - [x] Drop event files, verify list updates without manual refresh
  - [x] Verify grouping logic with sessions from multiple projects
  - [x] Verify visual distinction between active/stale/ended sessions
- **PR**: _TBD_
- **Notes**: SessionListViewModel uses ObservableObject with NotificationCenter-based updates. EventIngestionManager posts notifications after processing files. SessionContentView has collapsible SessionGroupView sections with SessionRowView showing status indicators (green circle=active, orange circle=stale, hollow circle=ended). Groups with active sessions sort first. 15 unit tests for the view model.

---

### Step 7: Session Liveness Detection

- **GitHub Issue**: #8
- **Type**: Auto
- **Complexity**: S
- **Status**: Complete
- **Dependencies**: Steps 2, 3
- **Acceptance Criteria**:
  - [x] A repeating timer checks all active sessions against the staleness timeout
  - [x] Sessions with no events within the timeout are marked as "stale" in the database
  - [x] Default timeout is 1 minute
  - [x] Timeout is configurable via settings (stored in SQLite `settings` table)
  - [x] Stale sessions that receive a new event are promoted back to "active"
  - [x] Sessions that receive a `SessionEnd` event are marked "ended" regardless of timeout
- **Testing / Verification**:
  - [x] Unit test: session with no activity past timeout → marked stale
  - [x] Unit test: stale session receiving new event → back to active
  - [x] Unit test: SessionEnd always marks ended
  - [x] Integration test: start session, wait > timeout, verify UI shows stale
- **PR**: _TBD_
- **Notes**: SessionLivenessMonitor uses DispatchSourceTimer on a utility-QoS queue with 10s check interval. Default timeout is 60s, configurable via `staleness_timeout` settings key. Existing upsert logic in EventIngestionManager handles stale-to-active promotion automatically. 18 unit tests covering timeout configuration, staleness detection, stale promotion, SessionEnd behavior, and callbacks.

---

### Step 8: Click Actions System

- **GitHub Issue**: #9
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Step 6
- **Acceptance Criteria**:
  - [x] Clicking a session row triggers the configured action
  - [x] Supported actions: open terminal at session's working directory, open session transcript file, copy session ID to clipboard, run custom shell command (with `$SESSION_ID`, `$CWD`, `$MODEL` substitution), send a macOS notification
  - [x] Action selection is stored in settings
  - [x] Custom shell command template is stored in settings
  - [x] Actions fail gracefully with user-visible error (e.g., transcript file not found)
- **Testing / Verification**:
  - [x] Test each action type individually
  - [x] Test custom shell command with variable substitution
  - [x] Test error handling when action target doesn't exist
- **PR**: _TBD_
- **Notes**: SessionClickAction enum with 5 action types. SessionActionHandler reads configured action from SQLite settings table (defaults to openTerminal). Open terminal tries iTerm2 first via AppleScript, falls back to Terminal.app. Custom commands support $SESSION_ID, $CWD, $MODEL substitution. Session rows have hover highlight and click handling wired through SessionGroupView. Error banner shown at bottom of session panel for 4 seconds. 25 unit tests covering all action types, variable substitution, settings persistence, and error handling.

---

### Step 9: Settings UI

- **GitHub Issue**: #10
- **Type**: Auto
- **Complexity**: M
- **Status**: Complete
- **Dependencies**: Steps 5, 7, 8
- **Acceptance Criteria**:
  - [x] Settings window accessible from the menu bar dropdown
  - [x] SwiftUI form with sections for: General, Window, Notifications, Actions
  - [x] General: staleness timeout (slider or stepper, in seconds/minutes)
  - [x] Window: always-on-top toggle, transparency slider
  - [x] Notifications: per-event-type toggles (SessionStart, SessionEnd, Stale)
  - [x] Actions: click action picker (dropdown), custom shell command text field
  - [x] Changes are persisted to SQLite `settings` table immediately
  - [x] Changes take effect immediately (no restart required)
- **Testing / Verification**:
  - [x] Change each setting, verify it persists after app restart
  - [x] Change window settings, verify floating window updates immediately
  - [x] Change staleness timeout, verify detection respects new value
- **PR**: _TBD_
- **Notes**: SettingsWindowController manages an NSWindow hosting SettingsView (SwiftUI Form with .grouped style). SettingsViewModel (ObservableObject) reads/writes all settings via @Published property didSet observers for immediate persistence. Callbacks wire transparency and always-on-top changes to SessionPanelController in real time. Settings keys are shared with SessionLivenessMonitor (staleness_timeout) and SessionActionHandler (click_action, custom_command_template). 25 unit tests covering persistence, loading, callbacks, value clamping, display formatting, and cross-component integration.

---

### Step 10: macOS Notifications

- **GitHub Issue**: #11
- **Type**: Auto
- **Complexity**: S
- **Status**: Complete
- **Dependencies**: Steps 3, 9
- **Acceptance Criteria**:
  - [x] App requests notification permission on first launch
  - [x] Notifications fire for SessionStart, SessionEnd, and Stale events (based on settings)
  - [x] Notification content includes session ID, project name, and event type
  - [x] Clicking a notification brings the floating window to the front
  - [x] Notifications respect the per-event-type toggles in settings
- **Testing / Verification**:
  - [x] Enable notifications for SessionStart, drop a SessionStart event file, verify notification appears
  - [x] Disable notifications for SessionStart, verify no notification
  - [x] Click notification, verify floating window activates
- **PR**: _TBD_
- **Notes**: NotificationManager uses UNUserNotificationCenter via a NotificationCenterProtocol abstraction for testability. Requests authorization with `.alert`, `.sound` options. Wired into EventIngestionManager (SessionStart/SessionEnd) and SessionLivenessMonitor (Stale) via callbacks. 24 unit tests covering all acceptance criteria.

---

### Step 11: Launch at Login

- **GitHub Issue**: #12
- **Type**: Auto
- **Complexity**: S
- **Status**: Complete
- **Dependencies**: Step 9
- **Acceptance Criteria**:
  - [x] Settings includes a "Launch at Login" toggle
  - [x] Toggle uses `SMAppService.mainApp` to register/unregister
  - [x] First launch prompts the user with an explanation of why launch-at-login is useful
  - [x] Current registration state is accurately reflected in the toggle
  - [x] Works on macOS 14+
- **Testing / Verification**:
  - [x] Toggle on, log out and back in, verify app launches
  - [x] Toggle off, log out and back in, verify app does not launch
  - [x] Verify toggle reflects actual system state
- **PR**: _TBD_
- **Notes**: LaunchAtLoginManager wraps SMAppService.mainApp behind a LaunchAtLoginServiceProtocol for testability. SettingsViewModel integrates the toggle with automatic revert on registration failure. First-launch prompt shown in a "Startup" section in the settings UI. Settings keys shared between LaunchAtLoginManager and SettingsViewModel. 17 unit tests covering all acceptance criteria.

---

### Step 12: Integration Testing & Polish

- **GitHub Issue**: #13
- **Type**: Manual
- **Complexity**: M
- **Dependencies**: Steps 1–11
- **Acceptance Criteria**:
  - [ ] End-to-end test: fresh install → hook auto-installation → start Claude session → session appears in window → click action fires
  - [ ] Verify hook installation doesn't corrupt existing Claude Code hooks
  - [ ] Verify high event volume (rapid tool use) doesn't cause lag or missed events
  - [ ] Verify stale detection works when Claude is force-killed
  - [ ] Verify settings changes take effect immediately
  - [ ] App icon and menu bar icon are appropriate
  - [ ] Memory usage stays reasonable over extended periods
- **Testing / Verification**:
  - [ ] Run full end-to-end scenario manually
  - [ ] Run with 3+ concurrent Claude sessions
  - [ ] Leave running for 1+ hours, check memory/CPU
- **PR**: _TBD_
- **Notes**: This step is manual because it requires running real Claude Code sessions and observing real-time behavior.

---

