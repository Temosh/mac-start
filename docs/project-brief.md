# Project Brief

## Product Summary

MacStart is a native macOS app launcher that brings back the Launchpad experience removed in macOS 26. A global hotkey opens a fullscreen overlay with a paged grid of app icons. The user can search, launch, organize into folders, and hide apps.

It is a personal tool, run on the developer's own Mac. It is either built locally from source or built by GitHub Actions and downloaded from the repository's releases. It is not distributed through the App Store or notarized.

## Users

- One user: the developer, on their own Mac.
- The overlay is often opened with a trackpad gesture. An external gesture tool (for example BetterTouchTool) maps the gesture to MacStart's hotkey. MacStart itself does not handle system trackpad gestures.

## Goals

- Fullscreen overlay that looks and behaves like Launchpad, shown on the main display.
- Toggle the overlay with a configurable global hotkey. The default is Option+S (`⌥S`).
- Show a Dock icon, like Launchpad. Clicking it toggles the overlay.
- A 7 × 5 grid by default, with rows and columns configurable in Settings.
- Launch at login, on by default and switchable off in Settings.
- Hide apps from the grid and unhide them later.
- Keep the app list correct. Each installed app appears exactly once. The grid follows installs, removals, and moves without duplicates or stale icons.
- Export the full layout to a file and import it back.
- Keep the layout across restarts. Layout means pages, order, folders, and hidden apps.
- Export everything (layout and all preferences) to one file, so moving to a new Mac is a single import.
- Act on several items at once in edit mode: select them by click, `⇧`-click, `⌘A`, or a rectangle, then move, group, or hide them together.

More features will follow. Each one is recorded here when it is agreed.

## Non-Goals

- Windowed or non-fullscreen modes. MacStart is fullscreen only.
- Showing the overlay on secondary displays.
- Handling trackpad gestures natively. Users bind gestures to the hotkey with external tools.
- App Store distribution, notarization, or App Sandbox.
- Supporting macOS versions before 27.

## Core Workflows

1. **Open and launch:** press the hotkey, the overlay appears, click an app (or search and press Return), the app launches, and the overlay closes.
2. **Search:** type while the overlay is open to filter apps by name. Hidden apps never appear in results.
3. **Organize:** drag icons to reorder them, move them between pages, or put them on a new page past the last one. Drop one app onto another to create a folder. Rename folders. In edit mode, select several items and move, group, or hide them together.
4. **Hide:** hide an app from the grid, and review or unhide hidden apps later.
5. **Back up and migrate:** export the layout and all preferences to a JSON file, and import it on the same or another Mac.
6. **Dismiss:** close the overlay with Escape, the hotkey, or a click on an empty area.

## Domain Terminology

| Term | Meaning |
|------|---------|
| Overlay | The fullscreen launcher surface that shows the grid |
| App | One installed `.app` bundle on disk. Two bundles are always two apps, even with the same bundle identifier |
| Catalog | The set of apps currently installed in the scanned locations |
| Layout | The user's arrangement: pages, items, folders, hidden apps |
| Page | One screen of the grid |
| Item | One grid slot: an app or a folder |
| Folder | A named group of apps that occupies one item slot |
| Hidden app | An installed app that the user excluded from the grid and from search |
| Preferences | User settings: hotkey, grid size, launch at login |
| Reconcile | Merging the catalog into the layout: new apps are added, removed apps are dropped, duplicates are collapsed |

Detailed rules: [domain-model.md](domain-model.md).

## Constraints And Assumptions

- macOS 27 or later, Apple silicon.
- Swift Package Manager only. There is no Xcode project, and agents do all the development.
- Signed ad hoc. No sandbox, no notarization. CI builds run on GitHub Actions (see [operations.md](operations.md)).
- Bundle identifier: `cc.summ.MacStart` (developer-owned domain `summ.cc`).

## Open Questions

None at the moment.
