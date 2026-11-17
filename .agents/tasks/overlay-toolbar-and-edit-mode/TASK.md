---
title: Add the overlay toolbar, edit mode, and new pages
type: feature
owner: agent+human
status: in-progress
depends_on: []
---

## Goal

Settings is easy to find from the overlay. The user can select several items and act on them together, and can create a new page by hand.

## Scope

The developer agreed to this design after an investigation. Each phase, and each input change inside a phase, goes to the developer as its own test build.

### Phase 1: toolbar (done)

- The search field is 38 pt tall and about 18% of the screen width (280 to 360 pt). It is centered halfway between the top of the screen and the top of the first row's icons (`GridMetrics.toolbarCenterY`).
- A round Settings button sits on the same line, ending at the right edge of the last column's icons (`GridMetrics.toolbarTrailingX`).
- Settings… is in the menu of the overlay's empty area. `⌘,` opens Settings while the overlay is open.

### Phase 2: edit mode

- An Edit button sits left of Settings, in the same style. The pair stays right-aligned to the same edge. While editing, the Edit button becomes a prominent Done button.
- Enter edit mode with the Edit button, or with `⌘`-click on a tile, which selects that tile. Leave it with Done, Escape, or by closing the overlay.
- In edit mode, a click selects or deselects a tile instead of launching it. `⇧`-click selects a range in reading order. `⌘A` selects every item on the page, or every search result. The selection persists across pages, and the count covers all pages.
- Search keeps working in edit mode, so "type a name, `⌘A`, New folder" works.
- Every tile shows a selection badge. A selected tile shows a checkmark and a highlight, so selection is never shown by color alone. No wiggle animation, and no tint over the whole overlay.
- An action bar floats above the page dots: the selection count, New folder, Move to page, Hide, and Deselect All. Inside an open folder it also offers Remove from folder.
- No Show in Finder in the bar: for many apps it opens a Finder window per folder. The single-app context menu keeps it.
- No `⌘⌫` shortcut for Hide: the search field has the focus, where `⌘⌫` deletes text, and a slip would hide many apps with no undo.
  - New folder takes apps only, because folders do not nest.
  - Move to page lists the pages plus New page.
  - Hide can be undone in Settings, under Hidden Apps.
- Right-click on a selected tile offers the same actions for the whole selection, as Finder does.
- Outside edit mode, an app's context menu also gets Move to page, with the pages plus New page.
- Escape order: cancel a drag, else close an open folder, else clear the search text, else leave edit mode, else close the overlay.
- Batch edits live in `MacStartCore/Editing` with unit tests. Reconcile keeps every invariant in `docs/domain-model.md`.

### Phase 3: later builds, one at a time

- Dragging past the last page creates a page. The dragged tile rests at the right edge of the last page, and the pager turns to a temporary empty page with a faint extra dot. A drop there makes the page real; leaving it removes the page. `LayoutEditing.moveItem` already adds a page for a destination one page past the last. `DragCoordinator.turnPage` currently stops at the last page.
- Rectangle selection by dragging on empty space in edit mode. The overlay-wide drag gesture already detects presses that hit no tile.
- Dragging several selected tiles at once.

### Out of scope

- A "+" button that makes an empty page. Pages are never empty (invariant 5 in `docs/domain-model.md`), so a page is created only by putting something on it.
- Trash or uninstall. Hide is the way to remove an app from the grid.
- Named page tabs, and icon-only toolbar buttons whose meaning is unclear.

## Acceptance Criteria

- Phase 1: the developer confirmed the toolbar by hand.
- Phase 2: every item above works by mouse and keyboard, with VoiceOver labels and the selected trait on selected tiles.
- Phase 3: each item works and was confirmed by hand in its own build.
- `docs/ui.md` describes every new control and interaction.

## Verification

- `swift build`, `swift test`, and `scripts/build-app.sh` succeed.
- Unit tests in `MacStartCoreTests` cover every batch edit, including New folder, Move to page, New page, and Hide on a selection that spans pages.
- The developer tests each build by hand before the next change starts.

## Notes

- Phase 1 is committed.
- Phase 2, build 1 is committed and confirmed by hand: edit mode in the grid and search results, with the Edit and Done buttons, click, `⌘`-click, `⇧`-click, `⌘A`, Return, Escape, badges, and the action bar with New Folder, Move to Page, Hide, and Show in Finder (since replaced by Deselect All). Core: `Item.ID` is a typed enum; `Layout.moveItems(_:toPage:pageCapacity:)` and `Layout.makeFolder(of:named:pageCapacity:)` with tests in `BatchEditingTests`.
- A click on empty space in edit mode does nothing, so a stray click never loses the selection. Deselect All clears it.
- The highlight box is 90% of the cell wide (`TileStyle.width`) for the keyboard selection and the edit selection, so neighboring highlights never touch. Selected items get the accent tint plus the checkmark badge.
- Phase 2, build 2: right-click on a selected tile for the same actions; Move to page in an app's context menu outside edit mode; edit mode inside an open folder with Remove from folder (how to open a folder in edit mode, for example with a double-click, is still open).
