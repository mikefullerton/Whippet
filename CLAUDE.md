# Whippet

A macOS menu bar app that monitors Claude Code sessions in real time.

## Project Overview

- **Platform**: macOS 14+
- **Language**: Swift
- **UI**: AppKit (NSPanel, NSStatusItem) + SwiftUI via NSHostingController
- **Storage**: SQLite
- **Architecture**: Menu bar app (LSUIElement) with floating session monitor window

## Build

```bash
xcodebuild -scheme Whippet -configuration Debug build
```

## Key Directories

- `Roadmaps/` — Feature planning documents and roadmaps
- `Whippet/` — Xcode project source code (once created)

## Conventions

- Use native SwiftUI/AppKit controls before building custom equivalents
- All lengthy tasks must be done asynchronously; never block the main thread
- Always use PRs and git worktrees; never commit directly to main
