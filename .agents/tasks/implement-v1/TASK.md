---
title: Implement MacStart v1
type: feature
owner: agent+human
status: in-progress
depends_on: []
---

## Goal

Build MacStart as specified in `docs/` and publish it as the GitHub Release `v0.1.0`. When this task is done, every goal and core workflow in `docs/project-brief.md` works in the built app.

## Scope

The specs are the source of truth: `docs/project-brief.md`, `docs/architecture.md`, `docs/domain-model.md`, `docs/ui.md`, and `docs/operations.md`. Follow the rules in `.agents/rules/`. This list says what each milestone covers, and the docs say how it behaves.

Do the milestones in order, one session each. M1 and M2 may share a session. When a milestone is done, tick it here, update the handoff notes, and move any settled fact into `docs/`.

- [ ] **M1 Scaffold.** `Package.swift` with the targets `MacStartCore`, `MacStart`, and `MacStartCoreTests`. `scripts/build-app.sh`. `Support/Info.plist`. A placeholder `Support/AppIcon.iconset`, drawn by `scripts/make-placeholder-icon.swift`. `.swift-format`. `.github/workflows/build.yml`. The app launches with a Dock icon and a main menu, and quits with Command-Q.
  Done when: the local checks pass, and CI is green on `master` after the push.
- [ ] **M2 Core domain.** In `MacStartCore`: the entities from `docs/domain-model.md` (`AppID`, `App`, `Catalog`, `Folder`, `Item`, `Page`, `Layout`, `Preferences`, `Export`), reconcile with all six invariants, the catalog scan of the three app roots, the JSON codec with `schemaVersion`, the atomic file store, and export and import with schema validation.
  Done when: `swift test` covers reconcile (duplicate collapsing, rebinding by bundle identifier, hidden apps kept when uninstalled, folder dissolving, page overflow, empty page removal), the export/import round trip, rejection of unknown schema versions, and catalog scanning against temporary bundle fixtures.
- [ ] **M3 Overlay and grid.** The Carbon hotkey (default Option-S), the Dock icon click and Dock menu, the overlay panel with its blur, placement, and animation, `LayoutStore`, the debounced FSEvents watcher, the icon cache, the paged grid with page dots and paging, launching, and closing (Escape, empty-area click, focus loss). The empty-catalog and launch-failure states from `docs/ui.md`.
  Done when: the developer confirms by hand that the hotkey and Dock icon toggle the overlay, and that apps launch.
- [ ] **M4 Search and keyboard.** Type-to-search into one results grid with hidden apps excluded, arrow keys and Return, the two-step Escape, the version subtitle for duplicate names, and the accessibility rules from `docs/ui.md` (labels, roles, keyboard use, Increase Contrast).
  Done when: the developer confirms search and keyboard use by hand.
- [ ] **M5 Organize.** Drag to reorder, drag to the screen edge to change page, drop an app onto an app to create a folder, the folder panel with inline rename, drag out of a folder, and the context menu (Show in Finder, Remove from Folder).
  Done when: the developer confirms drag and drop and folders by hand.
- [ ] **M6 Settings and release.** The settings window (Command-Comma and the Dock menu) with the hotkey recorder, grid size, the hidden apps list with Unhide, export and import with error alerts, and launch at login through `SMAppService`, re-registered at startup while the preference is on. Hide in the context menu. Then tag `v0.1.0`.
  Done when: the developer confirms the settings by hand, and the release zip installs with the steps in `docs/operations.md`.

## Acceptance Criteria

- Every goal and core workflow in `docs/project-brief.md` works in the built app.
- `swift build`, `swift test`, `scripts/build-app.sh`, and `swift format lint -r Sources Tests` pass locally, and CI is green on `master`.
- The GitHub Release `v0.1.0` exists, and its zip installs and runs as `docs/operations.md` describes.
- The developer has confirmed the manual checks of M3 to M6.

## Verification

- Every milestone: `swift build`, `swift test`, `scripts/build-app.sh`, `swift format lint -r Sources Tests`, then `open build/MacStart.app`.
- Commit and push only with the developer's go-ahead. CI results come from the `Build` workflow on GitHub (`gh run list`).
- Manual checks of the overlay, hotkey, drag and drop, and settings need the developer. An agent can launch the app and inspect the process, but cannot judge how it looks or feels.

## Notes

Handoff state:

- M1: every file is in place. On 2026-11-16, `swift build`, `swift test`, `scripts/build-app.sh`, and `swift format lint --strict -r Sources Tests` passed locally with no warnings. The built app runs as a foreground app with a Dock icon and logs `MacStart launched` under `cc.summ.MacStart:overlay`. M1 is committed. Still open: push it and get a green `Build` workflow run on GitHub; then tick M1.
- `MacStartCore` so far holds only `LogArea`, and the test target holds one smoke test. M2 adds the domain model and its tests.
