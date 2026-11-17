# UI

MacStart has one main surface, the fullscreen overlay, plus a settings window. The reference behavior is the classic macOS Launchpad.

## Overlay

- It covers the whole main display (`NSScreen.screens.first`), including the menu bar and Dock areas.
- It appears on the current Space, even over fullscreen apps.
- The background is a blurred view of the desktop.
- Showing and hiding use a short fade and scale animation. When Reduce Motion is on, it switches with no animation.
- Opening the app from Finder, or from the Dock while it is not running, shows the overlay. A launch at login keeps it hidden until the hotkey or the Dock icon opens it.

## Layout

- A search field is centered at the top, halfway between the top of the screen and the first row of icons. A round Settings button sits on the same line, ending at the right edge of the last column's icons.
- The paged grid fills the middle. Each item shows the app icon with its name below, truncated with an ellipsis. Apps that share a name also show their version below it.
- Page indicator dots sit at the bottom. Clicking a dot jumps to that page.
- The default grid is 7 columns by 5 rows. Both are configurable in Settings.

## Interactions

| Action | Result |
|--------|--------|
| Hotkey (default `⌥S`) | Toggles the overlay |
| Click Dock icon | Toggles the overlay |
| Escape | Cancels a drag, else closes an open folder, else clears the search text, else closes the overlay |
| Click on empty area | Closes the overlay |
| Click app | Launches it and closes the overlay |
| Horizontal two-finger swipe, scroll wheel, or arrow keys at the page edge | Changes page. A swipe moves the pages with the fingers; a short flick, or a slow swipe over 8% of the screen width, turns the page, and a spring settles it. Past the first or last page the pages stretch a little and spring back. A mouse wheel turns one page per notch |
| Typing | Goes to the search field, which has the focus while the overlay is open, and replaces the pages with one grid of the best results. Hidden apps are excluded |
| Arrow keys | Move a selection through the grid or the results. The first press selects the first item of the page. Left and right at the page edge go to the same row of the previous or next page |
| Return | Launches the selected app, or opens the selected folder. While searching, the best result is selected after every keystroke, so Return launches it |
| Drag app or folder | Reorders it. The dragged icon keeps the spot where it was grabbed under the pointer. The other icons make room once it rests between them for a moment, so moving onto an icon never pushes that icon away. Resting at the left or right screen edge turns the page |
| Rest a dragged app on an app, then drop | Creates a folder of both in the target's slot, named after the target app's App Store category, else the dropped app's, else "Folder" |
| Rest a dragged app on a folder, then drop | Adds the app to the end of the folder |
| Click folder | Opens the folder panel over a dimmed grid. The folder name is editable inline. A click outside the panel or Escape closes it; inside, the arrow keys and Return work as in the grid |
| Drag app inside folder panel | Reorders the folder's apps |
| Drag app out of folder panel | Closes the folder; the drop removes the app from the folder and places it in the grid, or in another folder |
| Right-click app | Context menu: Hide, Show in Finder, Remove from Folder (in folders) |
| Right-click empty area | Context menu: Settings… |
| `⌘,` | Opens Settings, also while the overlay is open |
| Losing focus (app switch, Space change) | Closes the overlay |

## Settings Window

Opened with the Settings button at the top of the overlay, Settings… in the menu of the overlay's empty area, `⌘,`, or Settings in the Dock icon menu. Opening it closes the overlay. `⌘W` closes it.

- **Shortcut** (default `⌥S`): click the recorder, then press the new shortcut; Escape cancels. A shortcut needs Command, Option, or Control, unless it is a function key. When another app already owns it, a message says so and the old shortcut stays.
- **Open at login** (on by default). When macOS needs the user to allow it, a message and an Open Login Items button appear.
- **Grid**: columns (3–15) and rows (2–10), default 7 × 5. A change reflows the pages at once.
- **Hidden Apps**: each hidden app with an Unhide button. Unhidden apps go to the end of the last page. Uninstalled hidden apps show "Not installed".
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
