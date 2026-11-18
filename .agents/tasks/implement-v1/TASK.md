---
title: Implement MacStart v1
type: feature
owner: agent+human
status: in-progress
depends_on: []
---

## Goal

Build MacStart as specified in `docs/`. When this task is done, every goal and core workflow in `docs/project-brief.md` works in the locally built app.

## Scope

The specs are the source of truth: `docs/project-brief.md`, `docs/architecture.md`, `docs/domain-model.md`, `docs/ui.md`, and `docs/operations.md`. Follow the rules in `.agents/rules/`. This list says what each milestone covers, and the docs say how it behaves.

Do the milestones in order, one session each. M1 and M2 may share a session. When a milestone is done, tick it here, update the handoff notes, and move any settled fact into `docs/`. No milestone depends on a push, a CI run, or a GitHub Release: the developer pushes when they decide.

- [x] **M1 Scaffold.** `Package.swift` with the targets `MacStartCore`, `MacStart`, and `MacStartCoreTests`. `scripts/build-app.sh`. `Support/Info.plist`. A placeholder `Support/AppIcon.iconset`, drawn by `scripts/make-placeholder-icon.swift`. `.swift-format`. `.github/workflows/build.yml`. The app launches with a Dock icon and a main menu, and quits with Command-Q.
  Done when: the local checks pass.
- [x] **M2 Core domain.** In `MacStartCore`: the entities from `docs/domain-model.md` (`AppID`, `InstalledApp`, `Catalog`, `Folder`, `Item`, `Page`, `Layout`, `Preferences`, `Export`), reconcile with all six invariants, the catalog scan of the three app roots, the JSON codec with `schemaVersion`, the atomic file store, and export and import with schema validation.
  Done when: `swift test` covers reconcile (duplicate collapsing, rebinding by bundle identifier, hidden apps kept when uninstalled, folder dissolving, page overflow, empty page removal), the export/import round trip, rejection of unknown schema versions, and catalog scanning against temporary bundle fixtures.
- [x] **M3 Overlay and grid.** The Carbon hotkey (default Option-S), the Dock icon click, the overlay panel with its blur, placement, and animation, `LayoutStore`, the debounced FSEvents watcher, the icon cache, the paged grid with page dots and paging, launching, and closing (Escape, empty-area click, focus loss). The empty-catalog and launch-failure states from `docs/ui.md`.
  Done when: the developer confirms by hand that the hotkey and Dock icon toggle the overlay, and that apps launch.
- [x] **M4 Search and keyboard.** Type-to-search into one results grid with hidden apps excluded, arrow keys and Return, the two-step Escape, the version subtitle for duplicate names, and the accessibility rules from `docs/ui.md` (labels, roles, keyboard use, Increase Contrast).
  Done when: the developer confirms search and keyboard use by hand.
- [x] **M5 Organize.** Drag to reorder, drag to the screen edge to change page, drop an app onto an app to create a folder, the folder panel with inline rename, drag out of a folder, and the context menu (Show in Finder, Remove from Folder).
  Done when: the developer confirms drag and drop and folders by hand.
- [ ] **M6 Settings.** The settings window (Command-Comma, and Settings in the Dock icon's menu, which M6 adds) with the hotkey recorder, grid size, the hidden apps list with Unhide, export and import with error alerts, and launch at login through `SMAppService`, re-registered at startup while the preference is on. Hide in the context menu.
  Done when: the developer confirms the settings by hand.

## Acceptance Criteria

- Every goal and core workflow in `docs/project-brief.md` works in the built app.
- `swift build`, `swift test`, `scripts/build-app.sh`, and `swift format lint -r Sources Tests` pass locally.
- The developer has confirmed the manual checks of M3 to M6.

## Verification

- Every milestone: `swift build`, `swift test`, `scripts/build-app.sh`, `swift format lint -r Sources Tests`, then `open build/MacStart.app`.
- Commit only with the developer's go-ahead, and never push. CI runs only when the developer pushes, so no check here depends on it.
- Manual checks of the overlay, hotkey, drag and drop, and settings need the developer. An agent can launch the app and inspect the process, but cannot judge how it looks or feels.

## Notes

Handoff state:

- M1: every file is in place. On 2026-11-16, `swift build`, `swift test`, `scripts/build-app.sh`, and `swift format lint --strict -r Sources Tests` passed locally with no warnings. The built app runs as a foreground app with a Dock icon and logs `MacStart launched` under `cc.summ.MacStart:overlay`. M1 is committed and done. The CI workflow has not run yet, because nothing is pushed.
- M2: done on 2026-11-16. 49 tests pass, including a seeded random reconcile test over 500 layouts. A scan of the developer's Mac found 112 apps in about 0.6 s, with Safari (a hidden-flagged link) included and duplicate links collapsed. The scan rules and file formats are in `docs/domain-model.md`.
- For M3, the Core entry points are:
  - `CatalogScanner(roots: CatalogScanner.standardRoots()).scan()`, which is synchronous file I/O, so run it off the main actor.
  - `layout.reconciled(with:pageCapacity:)`, with the capacity from `Preferences.pageCapacity`.
  - `LayoutFileStore(fileURL: LayoutFileStore.standardFileURL)` with `load()` and `save(_:)`.
  - `PreferencesStore().load()`, which returns nil before the first save. That marks the first launch, when launch at login gets registered.
  - `Export(jsonData:)` and `jsonData()` for import and export.
  - `invariantViolations(catalog:pageCapacity:)`, which can back a debug assertion in `LayoutStore`.
- Use `InstalledApp.bundleURL`, not the `AppID` path, for icons and launching, because it is the target of a linked app.
- M3: built on 2026-11-16; the developer checked it by hand and accepted it for now ("looks okish"). Build, 52 tests, lint, and packaging pass. The agent could not see the screen: it was locked with the display asleep. So the run was checked only through logs and window state:
  - At launch, the hotkey registers and the scan finds 112 apps. `layout.json` is written with pages of 35, 35, 35, and 7 items.
  - The panel covers the full display frame at alpha 1. Reopening the app (the Dock click event) hides it, and reopening again shows it.
  - While the display sleeps, the window server keeps new windows at 90% scale, because their opening transition never runs. That is the environment, not the app. Recheck with the display awake.
- Developer's checks for M3, all with the display awake:
  - Option-S and a click on the Dock icon toggle the overlay. It covers the whole main display, including the menu bar and the Dock, over a blur, with a short fade and zoom.
  - A click on an app launches it and closes the overlay. A click between icons, Escape, switching apps, or switching Spaces closes it. The app you were in gets the focus back.
  - A two-finger swipe, a mouse wheel, the left and right arrow keys, and the page dots all change pages.
  - The overlay also opens over a full-screen app.
- M6: built on 2026-11-16 and waiting for the developer's check by hand. 90 tests pass. The agent did not launch the app, because the developer was at the screen. The first launch of this build saves the default preferences and registers launch at login, which can show a Background Items notification.
- M6 rework, built on 2026-11-18 after the developer's first check found the one-page form growing with the hidden apps list, too-wide grid ranges, and grid changes that rearranged pages without asking. The window now has toolbar panes (General, Layout, Hidden Apps, Backup) per Apple's settings guidelines; the grid is one Grid size pop-up from 5 × 4 to 9 × 6 that asks to confirm ([ADR 0002](../../../docs/adr/0002-limit-the-grid-and-confirm-size-changes.md)); hidden apps get a search field, multiple selection, and one Unhide button. 119 tests pass. The panes were checked in offscreen renders only, never shown on the developer's screen. Waiting for the developer's check.
- Developer's checks for M6:
  - Command-Comma and Settings in the Dock icon's menu open the settings window, and the overlay closes.
  - The shortcut recorder takes a new shortcut, which works at once and is still there after a restart. Escape cancels. A plain letter is refused with a message.
  - Open at login registers MacStart in System Settings > General > Login Items, and turning it off removes it.
  - The window has toolbar buttons for General, Layout, Hidden Apps, and Backup; the title names the pane, and the window reopens on the last pane.
  - Picking a grid size asks to confirm; Change Grid reflows the pages, Cancel keeps the old size. Only 5 × 4 to 9 × 6 are offered.
  - Right-click > Hide removes an app from the grid and search. In Settings > Hidden Apps, search finds it, several can be selected, and Unhide puts them back at the end.
  - Export writes a JSON file. Import of that file asks to confirm, then restores the layout and settings. Importing a file that is not a backup shows an alert and changes nothing.
- When the developer accepts M6, every milestone is done. Then move any remaining facts from these notes into `docs/`, and delete this task folder with the developer's confirmation.
- M5: built on 2026-11-16; the developer tested it by hand, reported two issues (folders could not be made, dropped icons jumped back), both fixed, and accepted it. 86 tests pass; the layout edits (`Layout.moveItem`, `dropApp`, `removeApp(fromFolder:)`, `moveApp(inFolder:)`, `renameFolder`) are in `MacStartCore` and tested. The agent did not launch the app, because the developer was at the screen.
- Developer's checks for M5:
  - Dragging an icon makes the others shift live. The drop lands where the gap is, including on another page after resting at a screen edge.
  - Resting a dragged app on another app highlights it, and the drop makes a folder named after the app category. Dropping onto a folder adds the app.
  - A click on a folder opens its panel. The name edits in place. A click outside or Escape closes it. Arrows and Return work inside.
  - Dragging inside the folder reorders it. Dragging out closes the folder and places the app in the grid.
  - Right-click shows Show in Finder, plus Remove from Folder inside a folder.
  - A click on an icon still launches it, and a drag never launches.
- M4: built on 2026-11-16; the developer checked it by hand and accepted it for now ("looks okish"). 69 tests pass. Search ranking (`Layout.searchResults(matching:in:)`) and arrow-key movement (`GridNavigation`) are in `MacStartCore` and tested. The screen was locked, so only a launch smoke test ran: the overlay shows at 1800 x 1169, alpha 1, and toggles. Return on a selected folder does nothing until M5.
- Developer's checks for M4:
  - Typing filters to one grid of results right away, without clicking the field. The best match is first and highlighted, and Return launches it.
  - The arrow keys move the highlight through the results and through the grid. In the grid, left and right at the edge change page.
  - Escape clears the search first, and a second Escape closes the overlay.
  - Hidden apps never show up in results.
  - Apps that share a name show their version below it. On this Mac, two apps show as "Siri".
  - VoiceOver reads app names and the selection. Increase Contrast adds outlines and a stronger dimming.
