# UI

MacStart has one main surface, the fullscreen overlay, plus a settings window. The reference behavior is the classic macOS Launchpad.

## Overlay

- It covers the whole main display (`NSScreen.screens.first`), including the menu bar and Dock areas.
- It appears on the current Space, even over fullscreen apps.
- The background is a blurred view of the desktop.
- Showing and hiding use a short fade and scale animation. When Reduce Motion is on, it switches with no animation.
- Opening the app from Finder, or from the Dock while it is not running, shows the overlay. A launch at login keeps it hidden until the hotkey or the Dock icon opens it.

## Layout

- A search field is centered at the top.
- The paged grid fills the middle. Each item shows the app icon with its name below, truncated with an ellipsis. Apps that share a name also show their version below it.
- Page indicator dots sit at the bottom. Clicking a dot jumps to that page.
- The default grid is 7 columns by 5 rows. Both are configurable in Settings.

## Interactions

| Action | Result |
|--------|--------|
| Hotkey (default `⌥S`) | Toggles the overlay |
| Click Dock icon | Toggles the overlay |
| Escape | Clears the search text first; a second press closes the overlay |
| Click on empty area | Closes the overlay |
| Click app | Launches it and closes the overlay |
| Horizontal two-finger swipe, scroll wheel, or arrow keys at the page edge | Changes page |
| Typing | Goes to the search field, which has the focus while the overlay is open, and replaces the pages with one grid of the best results. Hidden apps are excluded |
| Arrow keys | Move a selection through the grid or the results. The first press selects the first item of the page. Left and right at the page edge go to the same row of the previous or next page |
| Return | Launches the selected app. While searching, the best result is selected after every keystroke, so Return launches it |
| Drag app | Reorders it; dragging to the screen edge moves it to the next or previous page |
| Drop app onto app | Creates a folder with a default name |
| Click folder | Opens the folder panel over a dimmed grid. The folder name is editable inline |
| Drag app out of folder panel | Removes it from the folder |
| Right-click app | Context menu: Hide, Show in Finder, Remove from Folder (in folders) |
| Losing focus (app switch, Space change) | Closes the overlay |

## Settings Window

Opened with `⌘,` while MacStart is active, or with Settings in the Dock icon menu.

- Hotkey recorder (default `⌥S`).
- Grid columns and rows (default 7 × 5).
- Hidden apps list with an Unhide button for each.
- Export and Import buttons, which use the standard save and open panels. An export covers the layout and every preference.
- Launch at login toggle (on by default).

## States

- **Empty catalog:** one empty page with a short message. This should never happen in practice.
- **Import failure:** an alert with the reason, and the layout and preferences are left unchanged.
- **App launch failure:** an alert with the app name and the underlying reason.

## Accessibility

- Every grid item exposes its app name as the accessibility label and has the button role.
- The grid, search, and folder panel are fully usable from the keyboard.
- The UI respects Reduce Motion and Increase Contrast. With Increase Contrast, the background is dimmed more, the selection and the search field get a white outline, page dots are brighter, and labels get a stronger shadow.
- While an input method composes text in the search field, the arrow keys, Return, and Escape go to the input method.
