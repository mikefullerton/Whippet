---
id: "roadmap-create-app-001"
created: "2026-03-24"
modified: "2026-03-24"
author: "mikefullerton"
definition-id: "feat-create-app-001"
change-history:
  - date: "2026-03-24"
    description: "Initial draft"
---

# Feature Roadmap: CreateApp (Whippet)

## Platform & Tools Summary

macOS app using Swift, AppKit (NSPanel, NSStatusItem, NSHostingController), SwiftUI, SQLite, FSEvents, UNUserNotificationCenter, and SMAppService. Consumes Claude Code hook events via a file-based drop directory.

## Progress

| Total Steps | Complete | In Progress | Blocked | Not Started |
|-------------|----------|-------------|---------|-------------|
| 12          | 3        | 0           | 0       | 9           |

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
- **Dependencies**: Step 3
- **Acceptance Criteria**:
  - [ ] On first launch, app reads `~/.claude/settings.json` (or creates it if missing)
  - [ ] Installs hooks for: SessionStart, SessionEnd, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop, Notification
  - [ ] Each hook writes a JSON file to `~/.claude/session-events/` with event type, session ID, timestamp, and relevant payload
  - [ ] Existing hooks in `settings.json` are preserved (merge, not overwrite)
  - [ ] App detects if its hooks are already installed and skips re-installation
  - [ ] Hook commands use portable shell syntax (no bash-specific features)
- **Testing / Verification**:
  - [ ] Test with empty `settings.json` — hooks are installed correctly
  - [ ] Test with existing hooks — Whippet hooks are appended, existing hooks untouched
  - [ ] Test with Whippet hooks already present — no duplicates created
  - [ ] Verify generated hook commands produce valid JSON files
- **PR**: _TBD_
- **Notes**: Hook commands will use `printf` or a small helper to write JSON. Each command must include the event type, session_id, timestamp, and event-specific fields from stdin via `jq`.

---

### Step 5: Floating Window Shell (NSPanel)

- **GitHub Issue**: #6
- **Type**: Auto
- **Complexity**: M
- **Dependencies**: Step 1
- **Acceptance Criteria**:
  - [ ] NSPanel created with `.floating` window level (default)
  - [ ] Window level is configurable (floating vs normal)
  - [ ] Window has configurable transparency (alpha value)
  - [ ] SwiftUI content hosted via NSHostingController
  - [ ] Panel toggles visibility from the menu bar "Show Sessions" item
  - [ ] Panel remembers its position between toggles
  - [ ] Panel has a clean, minimal chrome appropriate for a utility window
- **Testing / Verification**:
  - [ ] Launch app, toggle panel from menu bar — appears and disappears
  - [ ] Verify panel floats above other windows when set to floating
  - [ ] Verify transparency is adjustable
  - [ ] Move panel, hide, show — verify position is remembered
- **PR**: _TBD_
- **Notes**: NSPanel with `styleMask` including `.utilityWindow` and `.nonactivatingPanel` for proper floating behavior.

---

### Step 6: Session List UI

- **GitHub Issue**: #7
- **Type**: Auto
- **Complexity**: M
- **Dependencies**: Steps 2, 3, 5
- **Acceptance Criteria**:
  - [ ] SwiftUI view displays sessions from SQLite database
  - [ ] Sessions are grouped by repository/project (derived from working directory)
  - [ ] Each session row shows: working directory, model, time started, last activity, last tool used, status
  - [ ] Active sessions have a visual indicator distinct from stale and ended sessions
  - [ ] List updates in real time as new events are ingested
  - [ ] Empty state shown when no sessions exist
  - [ ] Groups are collapsible
- **Testing / Verification**:
  - [ ] Insert test session data into database, verify UI renders correctly
  - [ ] Drop event files, verify list updates without manual refresh
  - [ ] Verify grouping logic with sessions from multiple projects
  - [ ] Verify visual distinction between active/stale/ended sessions
- **PR**: _TBD_
- **Notes**: Use `@Observable` or `ObservableObject` pattern to bridge SQLite data to SwiftUI. Consider a lightweight publish/subscribe model from the ingestion layer.

---

### Step 7: Session Liveness Detection

- **GitHub Issue**: #8
- **Type**: Auto
- **Complexity**: S
- **Dependencies**: Steps 2, 3
- **Acceptance Criteria**:
  - [ ] A repeating timer checks all active sessions against the staleness timeout
  - [ ] Sessions with no events within the timeout are marked as "stale" in the database
  - [ ] Default timeout is 1 minute
  - [ ] Timeout is configurable via settings (stored in SQLite `settings` table)
  - [ ] Stale sessions that receive a new event are promoted back to "active"
  - [ ] Sessions that receive a `SessionEnd` event are marked "ended" regardless of timeout
- **Testing / Verification**:
  - [ ] Unit test: session with no activity past timeout → marked stale
  - [ ] Unit test: stale session receiving new event → back to active
  - [ ] Unit test: SessionEnd always marks ended
  - [ ] Integration test: start session, wait > timeout, verify UI shows stale
- **PR**: _TBD_
- **Notes**:

---

### Step 8: Click Actions System

- **GitHub Issue**: #9
- **Type**: Auto
- **Complexity**: M
- **Dependencies**: Step 6
- **Acceptance Criteria**:
  - [ ] Clicking a session row triggers the configured action
  - [ ] Supported actions: open terminal at session's working directory, open session transcript file, copy session ID to clipboard, run custom shell command (with `$SESSION_ID`, `$CWD`, `$MODEL` substitution), send a macOS notification
  - [ ] Action selection is stored in settings
  - [ ] Custom shell command template is stored in settings
  - [ ] Actions fail gracefully with user-visible error (e.g., transcript file not found)
- **Testing / Verification**:
  - [ ] Test each action type individually
  - [ ] Test custom shell command with variable substitution
  - [ ] Test error handling when action target doesn't exist
- **PR**: _TBD_
- **Notes**: "Open terminal" should open the default terminal app (Terminal.app or iTerm2) at the session's `cwd`.

---

### Step 9: Settings UI

- **GitHub Issue**: #10
- **Type**: Auto
- **Complexity**: M
- **Dependencies**: Steps 5, 7, 8
- **Acceptance Criteria**:
  - [ ] Settings window accessible from the menu bar dropdown
  - [ ] SwiftUI form with sections for: General, Window, Notifications, Actions
  - [ ] General: staleness timeout (slider or stepper, in seconds/minutes)
  - [ ] Window: always-on-top toggle, transparency slider
  - [ ] Notifications: per-event-type toggles (SessionStart, SessionEnd, Stale)
  - [ ] Actions: click action picker (dropdown), custom shell command text field
  - [ ] Changes are persisted to SQLite `settings` table immediately
  - [ ] Changes take effect immediately (no restart required)
- **Testing / Verification**:
  - [ ] Change each setting, verify it persists after app restart
  - [ ] Change window settings, verify floating window updates immediately
  - [ ] Change staleness timeout, verify detection respects new value
- **PR**: _TBD_
- **Notes**:

---

### Step 10: macOS Notifications

- **GitHub Issue**: #11
- **Type**: Auto
- **Complexity**: S
- **Dependencies**: Steps 3, 9
- **Acceptance Criteria**:
  - [ ] App requests notification permission on first launch
  - [ ] Notifications fire for SessionStart, SessionEnd, and Stale events (based on settings)
  - [ ] Notification content includes session ID, project name, and event type
  - [ ] Clicking a notification brings the floating window to the front
  - [ ] Notifications respect the per-event-type toggles in settings
- **Testing / Verification**:
  - [ ] Enable notifications for SessionStart, drop a SessionStart event file, verify notification appears
  - [ ] Disable notifications for SessionStart, verify no notification
  - [ ] Click notification, verify floating window activates
- **PR**: _TBD_
- **Notes**: Use `UNUserNotificationCenter`. Request authorization with `.alert`, `.sound` options.

---

### Step 11: Launch at Login

- **GitHub Issue**: #12
- **Type**: Auto
- **Complexity**: S
- **Dependencies**: Step 9
- **Acceptance Criteria**:
  - [ ] Settings includes a "Launch at Login" toggle
  - [ ] Toggle uses `SMAppService.mainApp` to register/unregister
  - [ ] First launch prompts the user with an explanation of why launch-at-login is useful
  - [ ] Current registration state is accurately reflected in the toggle
  - [ ] Works on macOS 14+
- **Testing / Verification**:
  - [ ] Toggle on, log out and back in, verify app launches
  - [ ] Toggle off, log out and back in, verify app does not launch
  - [ ] Verify toggle reflects actual system state
- **PR**: _TBD_
- **Notes**: `SMAppService` requires the app to be in `/Applications` or have a valid bundle identifier.

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

## Completion Checklist

- [ ] All steps marked Complete
- [ ] All GitHub issues closed
- [ ] All PRs merged
- [ ] Feature Definition updated with deviations
- [ ] Project docs updated (README, CHANGELOG, API docs as relevant)
- [ ] Feature Summary written
