# Domain Model

## Entities

```mermaid
erDiagram
    LAYOUT ||--o{ PAGE : "ordered pages"
    PAGE ||--o{ ITEM : "ordered slots"
    ITEM ||--o| APP_REF : "is an app"
    ITEM ||--o| FOLDER : "is a folder"
    FOLDER ||--o{ APP_REF : "ordered apps"
    LAYOUT ||--o{ APP_REF : "hidden set"
    APP_REF }o--|| APP : "resolves to (when installed)"
    CATALOG ||--o{ APP : "installed apps"
```

| Entity | Fields | Notes |
|--------|--------|-------|
| `AppID` | standardized bundle path + bundle identifier (if any) | The identity used everywhere in the layout. Two IDs are equal when their paths are equal, so every bundle on disk is a separate app. The bundle identifier lets reconcile follow an app that moved. |
| `InstalledApp` | id, display name, version, bundle URL | Comes from the catalog and is never persisted. The display name is the localized name Finder shows. The version is `CFBundleShortVersionString`. For an app found through a symbolic link, the bundle URL is the link's target, used for icons and launching. The icon is loaded on demand. |
| `Catalog` | set of `InstalledApp` keyed by `AppID` | Rebuilt by scanning the app locations, see [Catalog Scan](#catalog-scan). |
| `Folder` | stable UUID, name, ordered `[AppID]` | |
| `Item` | `.app(AppID)` or `.folder(Folder)` | |
| `Page` | ordered `[Item]` | Holds at most rows × columns items. |
| `Layout` | ordered `[Page]`, hidden `Set<AppID>` | Persisted in `layout.json` together with a schema version. |
| `Preferences` | hotkey (virtual key code + modifiers, default `⌥S`), grid columns × rows (default 7 × 5, columns 5–9, rows 4–6), launch at login (default on) | Persisted in `UserDefaults`. |
| `Export` | schema version, exported-at timestamp, `Layout`, `Preferences` | The complete state of the app, written to one file. |

## Invariants

1. Each `AppID` appears at most once in the layout, counting every page and every folder together.
2. An `AppID` is either placed in the layout or in the hidden set, never both.
3. Every placed `AppID` resolves to an installed app after reconcile.
4. A folder holds at least 2 apps. A folder left with 1 app dissolves into a plain item in the same slot. A folder left with 0 apps is removed.
5. No page is empty except page 1 when nothing is installed. Empty trailing pages are removed.
6. A page never holds more items than the grid capacity (columns × rows from `Preferences`). Extra items move onto the next page. When the grid size shrinks, the overflow cascades forward and order is preserved. User edits never cause this cascade (see below).

Reconcile enforces all six invariants. It runs after every catalog change, after an import, and at launch.

## Reconcile

Input: the catalog and the stored layout. Output: a layout that satisfies every invariant.

1. Collapse duplicates. When an `AppID` appears more than once, keep the first occurrence in reading order (page, then slot, then position inside the folder) and drop the rest. A placed app that is also hidden leaves the grid: hidden wins.
2. Match stored `AppID`s to the catalog, placed and hidden alike:
   - First, by exact path.
   - Then rebind the leftovers. If a stored entry has no path match, and its bundle identifier matches exactly one catalog app that is still unmatched, the entry takes that app's path. This covers an app moved between folders, or an export imported on a Mac with different install paths.
   - Entries are matched in a fixed order: placed entries in reading order, then hidden entries by path. When two leftovers could rebind to the same app, the earlier one wins.
   - A matched entry takes the catalog's `AppID`, so a changed bundle identifier at the same path is picked up.
   - Placed entries that are still unmatched are removed.
3. Keep unmatched hidden `AppID`s even when the app is uninstalled, so a reinstalled app stays hidden.
4. Append catalog apps that are neither placed nor hidden to the end of the last page, sorted by display name in Finder order, with ties broken by path.
5. Fix folders and pages as invariants 4–6 require.

Reconcile is a pure function from (catalog, layout, page capacity) to layout. It is unit tested without AppKit, including a seeded random test that checks every invariant and that a second reconcile changes nothing.

## Duplicate Bundles

Every `.app` bundle on disk is a separate app with its own icon, even when several bundles share one bundle identifier. Examples: a beta and a release build installed side by side, or two copies in different folders. Duplicate icons can come only from one bundle being entered twice, and invariant 1 rules that out.

When several bundles share a name, the grid shows the bundle version (`CFBundleShortVersionString`) as a subtitle so they can be told apart.

## Catalog Scan

The catalog holds every `.app` bundle with an `Info.plist` under `/Applications`, `/System/Applications`, and `~/Applications`:

- Folders are scanned recursively, but never inside a bundle, so helper apps inside other apps are not listed.
- Names starting with a dot are skipped. The hidden file flag is ignored, because `/Applications/Safari.app` is a symbolic link that carries it.
- A bundle without an `Info.plist` cannot be launched and is skipped. Some developer tools install such template bundles.
- A symbolic link to an app counts as that app, under the link's path. When a link and its target are both inside the scanned folders, the app is listed once, under the target's path.
- Wrapped iOS apps are read through their `WrappedBundle` link.
- Background-only and menu bar apps are listed like any other app. The user hides the ones they never launch.

## Editing

Every edit is followed by reconcile, so the invariants always hold. Positions count the way the overlay shows them during a drag: with the dragged item already taken out.

- Moving an item puts it into the destination slot; the items from there on move one slot later. A destination one page past the last page adds a page. An edit never pushes items to the next page: a move, taking apps out of a folder, or a new folder that would overfill a page is refused and changes nothing. Users arrange each page by hand, so one drop onto a full page would shift every later page, and putting the overflow on a new page instead would land it far from the drop. Only reconcile cascades overflow, because newly installed apps, unhidden apps, and a smaller grid have nowhere else to go.
- Dropping an app onto an app replaces the target with a folder of the target and the dropped app, in that order. The folder is named after the target app's App Store category (`LSApplicationCategoryType`, for example "Developer Tools"), else the dropped app's, else "Folder".
- Dropping an app onto a folder appends it. A folder cannot go into another folder.
- "Remove from Folder" puts the app into the slot right after the folder. A folder left with one app dissolves into that app.
- Moving several items to a page appends them to its end in reading order: page by page and slot by slot, with the apps of a folder in the folder's order. Apps leave their folders. A page one past the last adds as many pages at the end as the items fill. A page without room for all of them takes none.
- Making a folder of several apps puts it where the first of them is in reading order: in that app's slot, or right after the folder that holds it. It needs two or more placed apps. It is named after the first App Store category among them, else "Folder".
- Removing several apps from a folder puts them into the slots right after it, in the folder's order. Apps elsewhere stay where they are.
- Renaming trims surrounding whitespace; an empty name keeps the old one.
- Hiding adds the app to the hidden set, and reconcile takes it out of its slot or folder. Unhiding removes it from the set, and reconcile appends it to the last page like a new app.
- Resetting the layout starts over from an empty layout, so reconcile places every installed app as on the first launch. The hidden set empties; the preferences stay.
- A global shortcut needs Command, Option, or Control, unless its key is a function key (F1–F20), so it never takes a key away from typing.

## Search

Search matches only placed apps, including apps inside folders. Hidden apps never appear in results.

- The query and the display names are compared without case, diacritics, or width differences, and split into words at anything that is not a letter or a digit.
- An app matches when every word of the query appears in its name.
- Results are ranked: first, names that start with the first query word while every other word starts a word of the name; then names where every query word starts a word; then names that only contain the words. Within a rank, names keep Finder order.
- The overlay shows at most one page of results.

## Export And Import Format

- A single UTF-8 JSON file, extension `.json`, holding the full `Export`: `schemaVersion`, `exportedAt` (ISO 8601, UTC), `layout`, and `preferences`. The goal is a complete migration to a new Mac with one import.
- Folders, pages, and hidden apps refer to apps by `AppID` (path + bundle identifier). Icons are never exported. On a new Mac, apps installed at different paths are rebound by bundle identifier during reconcile.
- An import validates the schema version, replaces the current layout and preferences, re-registers the hotkey, applies the launch-at-login setting, and then runs reconcile. Apps that are missing on this Mac are dropped from placement but stay in the hidden set.
- An unknown or newer schema version is rejected with a user-facing error, and the current layout and preferences are left untouched.

### File Format

An export file in schema version 1:

```json
{
  "exportedAt" : "2026-11-16T12:00:00Z",
  "layout" : {
    "hidden" : [
      { "bundleIdentifier" : "com.apple.Chess", "path" : "/System/Applications/Chess.app" }
    ],
    "pages" : [
      {
        "items" : [
          { "app" : { "bundleIdentifier" : "com.apple.Safari", "path" : "/Applications/Safari.app" } },
          {
            "folder" : {
              "apps" : [
                { "bundleIdentifier" : "com.apple.Notes", "path" : "/System/Applications/Notes.app" },
                { "path" : "/Applications/Unsigned Tool.app" }
              ],
              "id" : "5B0B7D6E-8F0A-4C1E-9C3B-2F1D4E5A6B7C",
              "name" : "Work"
            }
          }
        ]
      }
    ]
  },
  "preferences" : {
    "gridColumns" : 7,
    "gridRows" : 5,
    "hotKey" : { "keyCode" : 1, "modifiers" : [ "option" ] },
    "launchAtLogin" : true
  },
  "schemaVersion" : 1
}
```

- Files are written pretty-printed with sorted keys, and hidden apps are sorted by path, so the same state always gives the same file.
- `exportedAt` is ISO 8601 in UTC, in whole seconds.
- An item is an object with exactly one key, `app` or `folder`. `bundleIdentifier` is left out when the bundle has none.
- `keyCode` is the virtual key code (`kVK_*`, `0x01` is S). `modifiers` lists `control`, `option`, `shift`, and `command`, in that order.
- `layout.json` holds `{ "schemaVersion" : 1, "layout" : { ... } }`. The preferences are stored as the JSON string `{ "schemaVersion" : 1, "preferences" : { ... } }` under the `UserDefaults` key `preferences`.
- Reading rejects invalid JSON, a missing field, a relative app path, an unknown modifier, and an item that is neither an app nor a folder. A grid size outside the allowed ranges is clamped to the nearest allowed size, so backups from versions that allowed more still import. Stored preferences that cannot be read are replaced by the defaults.
