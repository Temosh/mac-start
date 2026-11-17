# 0001. Never Push Items to the Next Page on a User Edit

- Status: Accepted
- Date: 2026-11-17

## Context

Moving items, taking apps out of a folder, and making a folder inserted items into a page and then cascaded the overflow onto the following pages, the same way reconcile does. Users arrange each page by hand, and one drop onto a full page shifted every later page and ruined that arrangement.

## Decision

A user edit adds items to a page only into its free slots. An edit that would overfill any page is refused and changes nothing. The overlay shows this before the edit: a full page opens no gap during a drag, and a drop there puts the item back; Move to Page marks pages without room as unavailable; New Folder and Remove from Folder are unavailable when the result would not fit. Resting a dragged app on an icon still makes or fills a folder on a full page, because that adds no item to the page. Moving items to a new page adds as many pages at the end as the items fill.

Reconcile still cascades overflow, because newly installed apps, unhidden apps, and a smaller grid have nowhere else to go.

## Alternatives Rejected

- Cascade the overflow, as before: it moves icons the user placed on other pages.
- Put the overflow on a new page at the end: the items land far from where the user dropped them.

## Consequences

Edits in `MacStartCore/Editing` return whether they applied, and `Layout.canMoveItems`, `canRemoveApps`, and `canMakeFolder` let the overlay disable targets without room. Making room on a full page is up to the user: move or hide items first, or use New Page.
