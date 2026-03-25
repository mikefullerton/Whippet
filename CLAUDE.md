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

This project uses component specs from the [litterbox](https://github.com/mikefullerton/litterbox) repo.

- **Expected path**: `../litterbox/`
- **Repo**: `git@github.com:mikefullerton/litterbox.git`
- Before reading any spec, verify `../litterbox/` exists. If it doesn't, ask the user whether to clone it.
- Component specs are in `../litterbox/` — read the spec and implement idiomatically for this project's platform.
- When implementing any feature or component, first check for an existing spec. If none exists, offer to create one following `../litterbox/ui/_template.md` and save it back to that repo.

## Conventions

- Use native SwiftUI/AppKit controls before building custom equivalents
- All lengthy tasks must be done asynchronously; never block the main thread
- Always use PRs and git worktrees; never commit directly to main
- After every batch of changes, commit and push immediately — do not let changes accumulate
