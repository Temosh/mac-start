# UI

MacStart has one main surface, the fullscreen overlay, plus a settings window. The reference behavior is the classic macOS Launchpad.

## Overlay

- It covers the whole main display (`NSScreen.screens.first`), including the menu bar and Dock areas.
- It appears on the current Space, even over fullscreen apps.
- The background is a blurred view of the desktop.
- Showing and hiding use a short fade and scale animation. When Reduce Motion is on, it switches with no animation.
- Opening the app from Finder, or from the Dock while it is not running, shows the overlay. A launch at login keeps it hidden until the hotkey or the Dock icon opens it.

## Layout

- A search field is centered at the top, halfway between the top of the screen and the first row of icons. Round Edit and Settings buttons sit on the same line, ending at the right edge of the last column's icons. In edit mode, Edit becomes a Done button in the accent color.
- The paged grid fills the middle. Each item shows the app icon with its name below, truncated with an ellipsis. Apps that share a name also show their version below it.
- Page indicator dots sit at the bottom. Clicking a dot jumps to that page.
- The default grid is 7 columns by 5 rows. Both are configurable in Settings.

## Interactions

| Action | Result |
|--------|--------|
| Hotkey (default `⌥S`) | Toggles the overlay |
| Click Dock icon | Toggles the overlay |
| Escape | Cancels a drag, else closes an open folder, else clears the search text, else leaves edit mode, else closes the overlay |
| Click on empty area | Closes the overlay. In edit mode it does nothing, so the selection stays |
| Click app | Launches it and closes the overlay |
| Pointer over an app or folder | Its icon grows 8%, as much as a dragged tile, with a 0.15 s ease-out, and shrinks back when the pointer leaves. The tile's click area counts, the name included. Nothing grows during a drag. With Reduce Motion, the size changes without animation |
| Horizontal two-finger swipe, scroll wheel, or arrow keys at the page edge | Changes page. A swipe moves the pages with the fingers; a short flick, or a slow swipe over 8% of the screen width, turns the page, and a spring settles it. Past the first or last page the pages stretch a little and spring back. A mouse wheel turns one page per notch |
| Typing | Goes to the search field, which has the focus while the overlay is open, and replaces the pages with one grid of the best results. Hidden apps are excluded |
| Arrow keys | Move a selection through the grid or the results. The first press selects the first item of the page. Left and right at the page edge go to the same row of the previous or next page |
| Return | Launches the selected app, or opens the selected folder. While searching, the best result is selected after every keystroke, so Return launches it |
| Drag app or folder | Reorders it, except in edit mode, which moves items with its actions and has no dragging. The dragged icon keeps the spot where it was grabbed under the pointer. The other icons make room once it rests between them for a moment, so moving onto an icon never pushes that icon away. Resting at the left or right screen edge turns the page. A full page makes no room: over it, the dragged icon fades and shows the system's gray prohibition mark (`Unsupported.icns`, the mark macOS puts on apps that cannot run) on its corner, and a drop puts the icon back instead of pushing icons to the next page. Resting on an icon there still makes or fills a folder, and the mark goes away once that drop target shows |
| Rest a dragged app on an app, then drop | Creates a folder of both in the target's slot, named after the target app's App Store category, else the dropped app's, else "Folder" |
| Rest a dragged app on a folder, then drop | Adds the app to the end of the folder |
| Click folder | Opens the folder panel over a dimmed grid. The panel grows out of the folder's icon with a 0.2 s ease-out and shrinks back into it when the folder closes, while the dimming fades; a folder that is not on the shown page grows from slightly smaller in place. With Reduce Motion, the panel appears and disappears without animation. The panel takes clicks and hover only once it has grown, and a closing panel takes none; a click there reaches the dimmed grid. The folder name is editable inline. A click outside the panel or Escape closes it; inside, the arrow keys and Return work as in the grid |
| Drag app inside folder panel | Reorders the folder's apps |
| Drag app out of folder panel | Closes the folder; the drop removes the app from the folder and places it in the grid, or in another folder |
| Right-click app | Context menu: Hide, Show in Finder, Move to Page, Remove from Folder (in folders) |
| Right-click folder | Context menu: Move to Page |
| Move to Page | Lists every page and New Page. Moves the item to the end of that page, closes an open folder, and shows the page. A page without room for the items is listed as unavailable, “(No Room)” |
| Right-click a selected item in edit mode | Context menu for the whole selection: New Folder with Selection, Move Selection to Page, Remove Selection from Folder (inside a folder), Hide Selection, Deselect All |
| Right-click empty area | Context menu: Settings… |
| Edit button, or `⌘`-click an item | Enters edit mode, also inside an open folder. `⌘`-click also selects that item |
| Open a folder in edit mode | A click opens it, as outside edit mode. Inside, a click, `⇧`-click, `⌘A`, and Return select its apps. Escape or a click outside the panel closes the folder and keeps edit mode |
| Click item in edit mode | A click on an app selects or deselects it instead of launching it. A click on a folder opens it, and a click on any item's round badge selects or deselects it. `⇧`-click selects every item from the last clicked one, in reading order. Return selects the keyboard-selected item. Selected items show a checkmark badge and an accent highlight; the selection stays across pages and searches |
| `⌘A` in edit mode | Selects every item on the current page, or every search result. Outside edit mode it selects the search text |
| Edit action bar | Shows above the page dots in edit mode, with the selection count. New Folder groups the selected apps where the first of them is; it needs two or more apps and no folders. Move to Page moves the selected items to the end of a page or a new page, then shows that page. Hide works on apps only. Deselect All clears the selection. Inside an open folder, Remove from Folder puts the folder's selected apps right after it. New Folder and Remove from Folder are unavailable when their result would not fit its page |
| Done | Leaves edit mode |
| `⌘,` | Opens Settings, also while the overlay is open |
| Losing focus (app switch, Space change) | Closes the overlay |

## Settings Window

Opened with the Settings button at the top of the overlay, Settings… in the menu of the overlay's empty area, `⌘,`, or Settings in the Dock icon menu. Opening it closes the overlay. `⌘W` closes it.

- **Shortcut** (default `⌥S`): click the recorder, then press the new shortcut; Escape cancels. A shortcut needs Command, Option, or Control, unless it is a function key. When another app already owns it, a message says so and the old shortcut stays.
- **Open at login** (on by default). When macOS needs the user to allow it, a message and an Open Login Items button appear.
- **Grid**: columns (3–15) and rows (2–10), default 7 × 5. A change reflows the pages at once.
- **Hidden Apps**: each hidden app with an Unhide button. Unhidden apps go to the end of the last page. Uninstalled hidden apps show "Not installed".
- **Layout**: Reset Layout… asks to confirm, then puts every installed app back in name order, as on the first launch, with no folders and no hidden apps. Settings stay. It cannot be undone; export a backup first to keep the old layout.
- **Backup**: Export and Import buttons with the standard save and open panels. An export covers the layout and every preference, named `MacStart Backup YYYY-MM-DD.json`. An import asks to confirm before it replaces anything.

## States

- **Empty catalog:** one empty page with a short message. This should never happen in practice.
- **Import failure:** an alert with the reason, and the layout and preferences are left unchanged. A newer format asks the user to update MacStart; a file that is not a backup is called damaged or not a MacStart backup.
- **App launch failure:** an alert with the app name and the underlying reason.

## Accessibility

- Every grid item exposes its app name as the accessibility label and has the button role.
- The grid, search, and folder panel are fully usable from the keyboard.
- VoiceOver reads the grid as "Apps" with its page, and its scroll commands turn pages.
- The UI respects Reduce Motion and Increase Contrast. With Increase Contrast, the background is dimmed more, the selection and the search field get a white outline, page dots are brighter, and labels get a stronger shadow.
- While an input method composes text in the search field, the arrow keys, Return, and Escape go to the input method.
