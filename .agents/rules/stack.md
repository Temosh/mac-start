# Stack Rules

## Runtime And Tooling

- Swift 6.4 toolchain from Xcode 27.2 (command-line use only). Swift language mode 6 with complete strict concurrency checking.
- Swift Package Manager is the only build system. `Package.swift` starts with `// swift-tools-version: 6.4` (the first version with `.v27`) and declares `platforms: [.macOS(.v27)]`.
- Never create, generate, or commit an `.xcodeproj` or `.xcworkspace`. Every build, test, and packaging step runs from the terminal.
- Commands: see `AGENTS.md` → Commands.
- `scripts/build-app.sh` does the following:
  - builds `-c release`;
  - assembles `build/MacStart.app` (`Contents/MacOS/MacStart`, `Contents/Info.plist` from `Support/Info.plist`, `Contents/Resources/AppIcon.icns` built by `iconutil` from `Support/AppIcon.iconset`);
  - signs it with `codesign --force --sign -`.
- `build/` and `*.app` are git-ignored.
- Formatting and linting use the `swift format` bundled with the toolchain. Once a `.swift-format` config exists, it owns the style.
- CI: GitHub Actions (`.github/workflows/build.yml`) on the `xcode-27` runner with Xcode 27.2 selected. It builds, tests, packages, and publishes the zipped app. Details: `docs/operations.md`.
- "Done" means `swift build`, `swift test`, and `scripts/build-app.sh` all succeed locally, and CI is green.
- `scripts/build-app.sh` must run unattended, without prompts or GUI tools, so the same script works locally and in CI.

## Frameworks

- SwiftUI for all views inside the overlay and settings.
- AppKit for the overlay `NSPanel`, `NSHostingView` bridging, `NSVisualEffectView`, `NSWorkspace`, the app delegate, and the settings window host.
- Carbon `RegisterEventHotKey` for the global hotkey. Do not use APIs that require Accessibility or Input Monitoring permission.
- Observation (`@Observable`) for UI-facing state. `LayoutStore` is `@MainActor` and owns the single mutable `Layout`.
- `ServiceManagement` (`SMAppService.mainApp`) for launch at login.
- Testing uses Swift Testing (`import Testing`, `@Test`, `#expect`). This overrides the XCTest default in `code-conventions-swift-macos.md`. XCTest is used only if UI tests are added later.

## Dependencies

- No third-party packages. Use the Apple SDK only.
- Adding any package needs the user's approval first. Record it here and in an ADR.

## Configuration

- `Support/Info.plist` holds bundle metadata:
  - `CFBundleIdentifier` `cc.summ.MacStart`
  - `LSMinimumSystemVersion` `27.0`
- Activation policy `.regular`: the app has a Dock icon.
- Preferences (hotkey, grid size, launch at login) live in `UserDefaults` under the bundle identifier. They are modeled as one `Preferences` value in `MacStartCore`, so export can include them.
- No secrets, environment variables, or network access.
- Logging uses `os.Logger` with subsystem `cc.summ.MacStart` and one category per area (`catalog`, `layout`, `overlay`, `hotkey`).

## Signing And Distribution

- Ad hoc signing only (`--sign -`). There is no Developer ID, notarization, or App Sandbox, and there are no entitlements.
- The app runs only on the developer's own Mac. It is built there or downloaded from this repository's GitHub Releases and workflow artifacts. Install steps: `docs/operations.md`.

## Persistence

- Layout: `~/Library/Application Support/MacStart/layout.json`. Written atomically, with a `schemaVersion` field.
- A schema change bumps `schemaVersion` and adds an explicit migration in `MacStartCore/Persistence`, covered by a fixture test.
- Export and import use one JSON file that holds the layout and all preferences. See `docs/domain-model.md`.
