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
| `AppID` | standardized bundle path + bundle identifier (if any) | The identity used everywhere in the layout. The path makes every bundle on disk a separate app. The bundle identifier lets reconcile follow an app that moved. |
| `App` | id, display name, bundle URL | Comes from the catalog and is never persisted as the source of truth. The icon is loaded on demand. |
| `Catalog` | set of `App` keyed by `AppID` | Rebuilt by scanning the app locations. |
| `Folder` | stable UUID, name, ordered `[AppID]` | |
| `Item` | `.app(AppID)` or `.folder(Folder)` | |
| `Page` | ordered `[Item]` | Holds at most rows × columns items. |
| `Layout` | schema version, ordered `[Page]`, hidden `Set<AppID>` | Persisted in `layout.json`. |
| `Preferences` | hotkey (key code + modifiers, default `⌥S`), grid columns × rows (default 7 × 5), launch at login (default on) | Persisted in `UserDefaults`. |
| `Export` | schema version, exported-at timestamp, `Layout`, `Preferences` | The complete state of the app, written to one file. |

## Invariants

1. Each `AppID` appears at most once in the layout, counting every page and every folder together.
2. An `AppID` is either placed in the layout or in the hidden set, never both.
3. Every placed `AppID` resolves to an installed app after reconcile.
4. A folder holds at least 2 apps. A folder left with 1 app dissolves into a plain item in the same slot. A folder left with 0 apps is removed.
5. No page is empty except page 1 when nothing is installed. Empty trailing pages are removed.
6. A page never holds more items than the grid capacity (columns × rows from `Preferences`). Extra items move onto the next page. When the grid size shrinks, the overflow cascades forward and order is preserved.

Reconcile enforces all six invariants. It runs after every catalog change, after an import, and at launch.

## Reconcile

Input: the catalog and the stored layout. Output: a layout that satisfies every invariant.

1. Collapse duplicates. When an `AppID` appears more than once, keep the first occurrence in reading order (page, then slot, then position inside the folder) and drop the rest.
2. Match stored `AppID`s to the catalog, placed and hidden alike:
   - First, by exact path.
   - Then rebind the leftovers. If a stored entry has no path match, and its bundle identifier matches exactly one catalog app that is still unmatched, the entry takes that app's path. This covers an app moved between folders, or an export imported on a Mac with different install paths.
   - Placed entries that are still unmatched are removed.
3. Keep unmatched hidden `AppID`s even when the app is uninstalled, so a reinstalled app stays hidden.
4. Append catalog apps that are neither placed nor hidden to the end of the last page, sorted by display name.
5. Fix folders and pages as invariants 4–6 require.

Reconcile is a pure function from (catalog, layout) to layout. It is unit tested without AppKit.

## Duplicate Bundles

Every `.app` bundle on disk is a separate app with its own icon, even when several bundles share one bundle identifier. Examples: a beta and a release build installed side by side, or two copies in different folders. Duplicate icons can come only from one bundle being entered twice, and invariant 1 rules that out.

When several bundles share a name, the grid shows the bundle version (`CFBundleShortVersionString`) as a subtitle so they can be told apart.

## Search

Search matches only placed apps, including apps inside folders. Hidden apps never appear in results.

## Export And Import Format

- A single UTF-8 JSON file, extension `.json`, holding the full `Export`: `schemaVersion`, `exportedAt` (ISO 8601, UTC), `layout`, and `preferences`. The goal is a complete migration to a new Mac with one import.
- Folders, pages, and hidden apps refer to apps by `AppID` (path + bundle identifier). Icons are never exported. On a new Mac, apps installed at different paths are rebound by bundle identifier during reconcile.
- An import validates the schema version, replaces the current layout and preferences, re-registers the hotkey, applies the launch-at-login setting, and then runs reconcile. Apps that are missing on this Mac are dropped from placement but stay in the hidden set.
- An unknown or newer schema version is rejected with a user-facing error, and the current layout and preferences are left untouched.
