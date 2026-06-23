# MotionDock Agent Instructions

## Project Overview
MotionDock is a SwiftUI-based macOS application.

## Development Principles
- Make small, focused changes.
- Avoid unnecessary refactoring.
- Do not modify unrelated files.
- Preserve the current architecture whenever possible.
- Prefer extending existing code over rewriting.
- Keep code readable and simple.

## UI Rules
- Dark mode first.
- Sidebar width: 240.
- Detail Panel width: 320.
- Use SF Symbols whenever appropriate.
- Maintain the existing design language.
- Keep spacing and typography consistent.

## Workflow
1. Read AGENTS.md.
2. Read README_PROGRESS.md.
3. Check TODO.md.
4. Identify only the files required for the task.
5. Implement changes.
6. Run builds and tests only after all modifications are complete.
7. Update README_PROGRESS.md.
8. Suggest a git commit message.

## Build
Prefer:

./scripts/build-app.sh

If unavailable:

swift build -c release

## Git Commit Format

feat:
fix:
refactor:
docs:
style:

## Constraints
- No large-scale restructuring unless explicitly requested.
- Avoid changing public APIs unless necessary.
- Keep diffs as small as possible.
