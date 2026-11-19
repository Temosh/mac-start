# Workflow Rules

How agents work with the developer on MacStart. The developer uses the Mac that builds and runs the app.

## Commits

- Commit only when the developer asks, straight to `master`. No branches or pull requests unless asked.
- Never push. The developer pushes, and CI runs only then, so no milestone or check depends on it.

## Checks By The Developer

- The developer checks the overlay, input, and settings by hand, with the display awake. An agent can build, launch, and inspect the process and its logs, but cannot judge how the app looks or feels.
- Each input change (gesture, scroll, drag, hover, click handling) goes to the developer as its own build, tested before the next one starts.
- For a visual choice, render every option side by side first, and build only the one the developer picks.

## The Developer's Focus

- Never run anything that opens windows, takes keyboard focus, or activates an app on the developer's Mac (test harnesses, key panels, replayed input) unless the developer approved it and confirmed they will leave the laptop alone while it runs. Ask before each batch.
- Relaunching MacStart after a build the developer asked for is fine; it opens the overlay once.
- Offscreen renders are fine: `ImageRenderer`, or a window that is never shown, in a process with the `.prohibited` activation policy.
- While the display sleeps or the screen is locked, window transitions and SwiftUI animations do not run, so renders and replays made then are not meaningful.

## Assets

- Icons, badges, and pointers come from system assets: SF Symbols, `NSCursor`, or the system's icon files. Never draw them from shapes.
