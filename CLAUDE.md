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

## Shared Component Specs

UI component specs are at `../litterbox/ui/` — when implementing a component from a spec, read the spec file and implement it idiomatically for this project's platform.

## Conventions

- Use native SwiftUI/AppKit controls before building custom equivalents
- All lengthy tasks must be done asynchronously; never block the main thread
- Always use PRs and git worktrees; never commit directly to main
- After every batch of changes, commit and push immediately — do not let changes accumulate
