# Canopy - Development Guide

## Overview
Canopy is a native macOS GraphQL client built with Swift and SwiftUI.

## Prerequisites
- macOS 15.0+ (Sequoia or later)
- Xcode 16.0+
- XcodeGen (`brew install xcodegen`)

## Project Setup
The Xcode project is generated from `project.yml` using XcodeGen.
The `.xcodeproj` is gitignored — you must generate it locally.

```bash
xcodegen generate
# Or: make project
```

## Build
```bash
make build
```

## Test
```bash
make test
```

## Open in Xcode
```bash
make open
```

## Project Structure
- `project.yml` — XcodeGen project spec (source of truth for project config)
- `Canopy/` — Main app source code
  - `App/` — App entry point and top-level state
  - `Views/` — SwiftUI views
  - `Models/` — Data models
  - `Networking/` — HTTP/GraphQL networking layer
  - `Features/` — Feature modules (QueryEditor, ResultViewer, etc.)
  - `Resources/` — Asset catalogs, preview content
- `CanopyTests/` — Unit tests

## Architecture
- **UI Framework:** SwiftUI with `@Observable` (requires macOS 15+)
- **Deployment Target:** macOS 15.0 (Sequoia)
- **Networking:** URLSession
- **Dependencies:** Managed via Swift Package Manager (declared in project.yml)

## Key Commands
- `make project` — Regenerate .xcodeproj from project.yml
- `make build` — Build debug configuration
- `make test` — Run unit tests
- `make release` — Build release configuration
- `make clean` — Remove build artifacts and generated project
- `make open` — Open in Xcode

## Adding Dependencies
Add Swift packages to `project.yml` under the `packages` key:
```yaml
packages:
  SomePackage:
    url: https://github.com/user/SomePackage
    from: "1.0.0"
```
Then add the package to the target's `dependencies` list and run `xcodegen generate`.

## Conventions
- Use Swift Testing framework (`import Testing`, `@Test`, `#expect`) for new tests, not XCTest
- Use `@Observable` macro for state management, not `ObservableObject`
- Follow standard Swift naming conventions
- Keep views small and composable
