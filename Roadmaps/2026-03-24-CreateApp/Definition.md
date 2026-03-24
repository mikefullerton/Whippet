---
id: "feat-create-app-001"
created: "2026-03-24"
modified: "2026-03-24"
author: "mikefullerton"
change-history:
  - date: "2026-03-24"
    description: "Initial draft"
---

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

## Deviations from Plan

_Filled in at completion — what changed from the original plan and why._
